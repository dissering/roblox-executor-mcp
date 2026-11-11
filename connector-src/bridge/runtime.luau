return function(context)
local CreateBridge = context.CreateBridge
local Environment = context.Environment
local WaitForBridgeClientId = context.WaitForBridgeClientId
local ScriptMappingPipeline = context.ScriptMappingPipeline
local StartUploadQueue = context.StartUploadQueue
local PublishScriptMappingStatus = context.PublishScriptMappingStatus
local ResetScriptMappingState = context.ResetScriptMappingState
local StartScriptMapping = context.StartScriptMapping
local StartFailedScriptResync = context.StartFailedScriptResync
local ResumeDeferredScriptMappings = context.ResumeDeferredScriptMappings
local IsCurrentConnector = context.IsCurrentConnector or function() return true end
--// Main Loop \\--
-- Report state changes so a connector that cannot reach the server is not silent.
-- Repeats of the same message are suppressed.
local lastStatus
local function Report(level, message)
    if message == lastStatus then return end
    lastStatus = message
    local output = if level == "warn" then warn else print
    output("[roblox-mcp] " .. message)
end

Report("print", "connector loaded, connecting to " .. tostring(Environment.BridgeURL))

while IsCurrentConnector() do
    local success, Bridge = pcall(CreateBridge)

    if not IsCurrentConnector() then
        if success then Bridge:Destroy() end
        break
    end

    if not success then
        Report("warn", "cannot connect: " .. tostring(Bridge) .. " (retrying)")
        task.wait(3)
        continue
    end

    local clientId = WaitForBridgeClientId(Bridge)
    if clientId then
        Report("print", "connected to " .. tostring(Environment.BridgeURL)
            .. " via " .. (if Bridge.WebSocket then "WebSocket" else "HTTP polling")
            .. " as " .. tostring(clientId))
        ScriptMappingPipeline.bridge = Bridge
        StartUploadQueue()

        if ScriptMappingPipeline.clientId ~= clientId then
            ResetScriptMappingState(clientId)
        end

        -- Mapping decompiles every script in the background. It is heavy enough to crash
        -- some clients, so it only runs when explicitly enabled.
        if Environment.EnableScriptMapping == true or Environment.MCP_ScriptMappingStarted == true then
            StartScriptMapping(clientId)
            StartFailedScriptResync()
            ResumeDeferredScriptMappings()
            PublishScriptMappingStatus()
        else
            ScriptMappingPipeline.clientId = clientId
            ScriptMappingPipeline.disabled = true
            ScriptMappingPipeline.stateVersion += 1
            PublishScriptMappingStatus()
        end
    end

    local registrars = {
        require("./handlers/core"),
        require("./handlers/scripts"),
        require("./handlers/instances"),
        require("./handlers/remote-spy/logs"),
        require("./handlers/remote-spy/control"),
        require("./handlers/input"),
    }
    for _, registerHandlers in registrars do
        registerHandlers(context, Bridge)
    end

    if not clientId then
        Report("warn", "connected, but the server never confirmed registration")
    end

    -- Also stop waiting when a newer connector takes over this session.
    while Bridge.Connected and IsCurrentConnector() do
        task.wait(0.25)
    end
    local replaced = Bridge.Replaced == true
    if replaced then
        Report("warn", "another connector took over this session, stopping this one")
    elseif IsCurrentConnector() then
        Report("warn", "disconnected: " .. tostring(Bridge.DisconnectReason or "unknown reason") .. ", reconnecting")
    end
    Bridge:Destroy()

    if ScriptMappingPipeline.bridge == Bridge then
        ScriptMappingPipeline.bridge = nil
    end
    if replaced then
        return
    end
    task.wait(1)
end

print("[roblox-mcp] previous connector stopped, a newer one took over")
end
