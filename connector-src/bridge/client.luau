return function(context)
local HttpService = context.HttpService
local BridgeURL = context.BridgeURL
local WebSocketAvailable = context.WebSocketAvailable
local GetRegistrationInfo = context.GetRegistrationInfo
local SanitizeForOutput = context.SanitizeForOutput
local LuaEncode = context.LuaEncode

--// Base Bridge Class \\--
local BaseBridge = {}; do
    BaseBridge.__index = BaseBridge
    
    function BaseBridge:BindToType(type, callback)
        self.Callbacks[type] = callback
    end

    function BaseBridge:BindToTypeRaw(type, callback)
        self.Callbacks[type] = callback
        self.RawCallbacks = self.RawCallbacks or {}
        self.RawCallbacks[type] = true
    end

    function BaseBridge:CreateAlias(type, aliases)
        for _, alias in aliases do
            self.Callbacks[alias] = self.Callbacks[type]
            if self.RawCallbacks and self.RawCallbacks[type] then
                self.RawCallbacks[alias] = true
            end
        end
    end

    function BaseBridge:Destroy()
        self.Connected = false
        for _, field in { "AliveThread", "PollThread", "ProbeThread" } do
            local thread = self[field]
            self[field] = nil
            if thread then pcall(task.cancel, thread) end
        end
        for _, field in { "MessageConnection", "CloseConnection" } do
            local connection = self[field]
            self[field] = nil
            if connection then connection:Disconnect() end
        end
        if self.WebSocket then
            pcall(function() self.WebSocket:Close() end)
            self.WebSocket = nil
        end
        table.clear(self.Callbacks)
        if self.RawCallbacks then table.clear(self.RawCallbacks) end
    end

    function BaseBridge:HandleMessage(data)
        if self.Callbacks[data.type] then
            local success, result = pcall(function()
                return self.Callbacks[data.type](data)
            end)

            if success and result == nil then
                return nil
            end

            if not success then
                return self:FormatResponse(result, data.id, true)
            end

            if self.RawCallbacks and self.RawCallbacks[data.type] then
                return {
                    output = tostring(result),
                    success = true,
                    id = data.id
                }
            end

            return self:FormatResponse(result, data.id, false)
        end
        return nil
    end
    
    function BaseBridge:FormatResponse(message, id, isError)
        if isError then
            return {
                error = tostring(message),
                success = false,
                id = id
            }
        end
        
        local output = SanitizeForOutput(message)
        if typeof(output) ~= "table" then
            output = { output }
        end
    
        return {
            output = LuaEncode(output, {
                Prettify = false
            }),
            success = true,
            id = id
        }
    end
    
    function BaseBridge:IsAlive()
        local success, result = pcall(function()
            local response
            local thread = task.spawn(function()
                local success, data = pcall(request, {
                    Url = "http://" .. BridgeURL,
                    Method = "GET"
                })

                if success then
                    response = data
                end
            end)
            self.ProbeThread = thread

            local start = os.clock()
            repeat task.wait(0.05) until response ~= nil or os.clock() - start > 5
            self.ProbeThread = nil

            if response == nil then
                task.cancel(thread)
                return false
            end
    
            -- 426 = Upgrade Required (WebSocket), 200 = HTTP mode
            if response.StatusCode == 426 or response.StatusCode == 200 then
                return true
            end
    
            return false
        end)
    
        if not success then
            return false
        end
    
        return result
    end
end

--// WebSocket Bridge \\--
local WebSocketBridge = setmetatable({}, {__index = BaseBridge}); do
    WebSocketBridge.__index = WebSocketBridge
    
    function WebSocketBridge.new()
        local self = setmetatable({}, WebSocketBridge)
    
        --// Yield until the server is alive with exponential backoff \\--
        local retryDelay = 0.5
        local maxRetryDelay = 5
        local maxAttempts = 10
        local attempts = 0
        
        while not self:IsAlive() do
            attempts += 1
            if attempts >= maxAttempts then
                error("Failed to connect to bridge server after " .. maxAttempts .. " attempts")
            end
            task.wait(retryDelay)
            retryDelay = math.min(retryDelay * 1.5, maxRetryDelay)
        end
    
        --// Connect to the server with timeout \\--
        local wsConnection = nil
        local connectionThread = task.spawn(function()
            local success, result = pcall(function()
                return WebSocket.connect("ws://" .. BridgeURL)
            end)
            if success then
                wsConnection = result
            end
        end)
        
        local connectionStart = os.clock()
        repeat task.wait(0.05) until wsConnection ~= nil or os.clock() - connectionStart > 5
        
        if wsConnection == nil then
            task.cancel(connectionThread)
            error("WebSocket connection timed out after 5 seconds")
        end
        
        self.WebSocket = wsConnection
        self.Connected = true
        self.Callbacks = {}
        self.ClientId = nil

        self.AliveThread = task.spawn(function()
            local consecutiveFailures = 0
            while self.Connected do
                task.wait(1)
                if not self.Connected then
                    break
                end

                if self:IsAlive() then
                    consecutiveFailures = 0
                    continue
                end

                consecutiveFailures += 1
                if consecutiveFailures < 3 then
                    continue
                end
                
                self.Connected = false
                break
            end
    
            pcall(function()
                self.WebSocket:Close()
            end)
        end)
    
        --// On Message \\--
        self.MessageConnection = self.WebSocket.OnMessage:Connect(function(message)
            local data = HttpService:JSONDecode(message)

            --// Handle registration response \\--
            if data.type == "registered" then
                self.ClientId = data.clientId
                return
            end

            local response = self:HandleMessage(data)
            if response then
                self.WebSocket:Send(HttpService:JSONEncode(response))
            end
        end)
    
        --// On Close \\--
        self.CloseConnection = self.WebSocket.OnClose:Connect(function()
            self.Connected = false
        end)

        local registered, registrationError = pcall(function()
            self.WebSocket:Send(HttpService:JSONEncode(GetRegistrationInfo()))
        end)
        if not registered then
            self:Destroy()
            error(registrationError)
        end
    
        return self
    end
    
    function WebSocketBridge:WaitForDisconnect()
        while self.Connected do
            task.wait(0.1)
        end
    end
end

--// HTTP Polling Bridge \\--
local HTTPBridge = setmetatable({}, {__index = BaseBridge}); do
    HTTPBridge.__index = HTTPBridge
    
    function HTTPBridge.new()
        local self = setmetatable({}, HTTPBridge)
    
        --// Yield until the server is alive with exponential backoff \\--
        local retryDelay = 0.5
        local maxRetryDelay = 5
        local maxAttempts = 10
        local attempts = 0
        
        while not self:IsAlive() do
            attempts += 1
            if attempts >= maxAttempts then
                error("Failed to connect to bridge server after " .. maxAttempts .. " attempts")
            end
            task.wait(retryDelay)
            retryDelay = math.min(retryDelay * 1.5, maxRetryDelay)
        end
    
        self.Connected = true
        self.Callbacks = {}
        self.PollInterval = 0.1
        self.ClientId = nil

        --// Register with the server \\--
        pcall(function()
            local regResponse = request({
                Url = "http://" .. BridgeURL .. "/register",
                Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = HttpService:JSONEncode(GetRegistrationInfo()),
            })
            if regResponse.StatusCode == 200 and regResponse.Body then
                local regData = HttpService:JSONDecode(regResponse.Body)
                self.ClientId = regData.clientId
            end
        end)
    
        --// Start polling thread \\--
        self.PollThread = task.spawn(function()
            local consecutiveFailures = 0
            
            while self.Connected do
                local gotCommands = false
                local success, _ = pcall(function()
                    local pollUrl = "http://" .. BridgeURL .. "/poll"
                    if self.ClientId then
                        pollUrl = pollUrl .. "?clientId=" .. self.ClientId
                    end
                    local response = request({
                        Url = pollUrl,
                        Method = "GET"
                    })

                    --// Server might be down \\--
                    if response.StatusCode ~= 204 and response.StatusCode ~= 200 then
                        consecutiveFailures += 1
                        if consecutiveFailures >= 3 then
                            self.Connected = false
                        end

                        return
                    end
                    
                    consecutiveFailures = 0
    
                    --// Handle response \\--
                    if response.Body and response.Body ~= "" then
                        local data = HttpService:JSONDecode(response.Body)
                        local commands = {}
                        if typeof(data) == "table" and data.type == nil and #data > 0 then
                            commands = data
                        elseif typeof(data) == "table" and data.type ~= nil then
                            commands = { data }
                        end

                        for _, command in ipairs(commands) do
                            gotCommands = true
                            task.spawn(function()
                                local result = self:HandleMessage(command)
                                if result == nil then return end

                                --// Send response back \\--
                                request({
                                    Url = "http://" .. BridgeURL .. "/respond",
                                    Method = "POST",
                                    Headers = {
                                        ["Content-Type"] = "application/json"
                                    },
                                    Body = HttpService:JSONEncode(result)
                                })
                            end)
                        end
                    end
                end)
    
                if not success then
                    consecutiveFailures += 1
                    if consecutiveFailures >= 3 then
                        self.Connected = false
                    end
                end
    
                if not gotCommands then
                    task.wait(self.PollInterval)
                end
            end
        end)
    
        return self
    end
    
    function HTTPBridge:WaitForDisconnect()
        while self.Connected do
            task.wait(0.1)
        end
    end
end

--// Create Bridge \\--
local function CreateBridge()
    if WebSocketAvailable then
        local success, bridge = pcall(function()
            return WebSocketBridge.new()
        end)
        
        if success then
            return bridge
        end
    end

    return HTTPBridge.new()
end

return {
    CreateBridge = CreateBridge,
}
end
