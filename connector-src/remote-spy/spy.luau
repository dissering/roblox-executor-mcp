--!nocheck
-- Built-in remote spy.
--
-- Outgoing calls are intercepted with the strongest mechanism the executor offers:
--   1. hookmetamethod(game, "__namecall")          (log + block)
--   2. getrawmetatable(game).__namecall swap        (log + block)
--   3. hookfunction on FireServer / InvokeServer    (log + block, catches direct calls)
-- Incoming RemoteEvent traffic is logged by connecting to OnClientEvent, which needs no
-- executor APIs at all. Blocking incoming events needs getconnections.

local RemoteSpy = {}
RemoteSpy.__index = RemoteSpy

local OUTGOING_METHODS = {
    RemoteEvent = "FireServer",
    UnreliableRemoteEvent = "FireServer",
    RemoteFunction = "InvokeServer",
    BindableEvent = "Fire",
    BindableFunction = "Invoke",
}
local BINDABLE_CLASSES = { BindableEvent = true, BindableFunction = true }
local INCOMING_CLASSES = { RemoteEvent = true, UnreliableRemoteEvent = true }
local HOOKED_METHOD_NAMES = { FireServer = true, InvokeServer = true, Fire = true, Invoke = true }

local MAX_CALLS_PER_REMOTE = 50
local MAX_REMOTES_PER_DIRECTION = 1000

local function identity(fn)
    return fn
end

local function newDirectionTable()
    return { Outgoing = {}, Incoming = {} }
end

function RemoteSpy.new(deps)
    local self = setmetatable({}, RemoteSpy)
    self.Lookup = deps.Lookup
    self.Game = deps.Game
    self.InstanceNew = deps.InstanceNew
    self.TypeOf = deps.TypeOf or typeof
    self.Clock = deps.Clock or os.clock
    self.Encode = deps.LuaEncode

    self.Enabled = true
    self.IncludeBindables = false
    self.IncludeExecutorCalls = false

    self.Logs = newDirectionTable()
    self.RemoteCounts = { Outgoing = 0, Incoming = 0 }
    self.BlockRules = newDirectionTable()
    self.IgnoreRules = newDirectionTable()

    self.OutgoingMode = "unavailable"
    self.FunctionHooks = 0
    self.IncomingMode = "unavailable"
    self.Watched = setmetatable({}, { __mode = "k" })
    self.WatchedCount = 0
    self.InNamecall = setmetatable({}, { __mode = "k" })
    self.Notes = {}
    return self
end

function RemoteSpy:SafeIndex(instance, key)
    local ok, value = pcall(function()
        return instance[key]
    end)
    if ok then return value end
    return nil
end

function RemoteSpy:IsTarget(instance, method)
    if self.TypeOf(instance) ~= "Instance" then return false end
    local class = self:SafeIndex(instance, "ClassName")
    if OUTGOING_METHODS[class] ~= method then return false end
    if BINDABLE_CLASSES[class] and not self.IncludeBindables then return false end
    return true
end

-- Records a call. Returns true when the call must be blocked.
function RemoteSpy:Record(instance, direction, method, args, meta)
    if not self.Enabled then return false end
    local name = self:SafeIndex(instance, "Name") or "?"
    local blocked = self.BlockRules[direction][name] == true
    if self.IgnoreRules[direction][name] then return blocked end

    local logs = self.Logs[direction]
    local log = logs[instance]
    if not log then
        if self.RemoteCounts[direction] >= MAX_REMOTES_PER_DIRECTION then return blocked end
        log = {
            Instance = instance,
            Name = name,
            ClassName = self:SafeIndex(instance, "ClassName") or "?",
            Direction = direction,
            Method = method,
            Calls = {},
            Head = 0,
            TotalCalls = 0,
            FirstSeen = self.Clock(),
        }
        logs[instance] = log
        self.RemoteCounts[direction] += 1
    end

    log.Name = name
    log.TotalCalls += 1
    log.LastSeen = self.Clock()
    log.Head = log.Head % MAX_CALLS_PER_REMOTE + 1
    log.Calls[log.Head] = {
        Number = log.TotalCalls,
        Arguments = args,
        Time = log.LastSeen,
        Script = meta and meta.Script or nil,
        IsExecutor = meta and meta.IsExecutor or false,
        Blocked = blocked,
    }
    return blocked
end

-- Oldest first, at most `count` of the buffered calls.
function RemoteSpy:RecentCalls(log, count)
    local stored = math.min(log.TotalCalls, MAX_CALLS_PER_REMOTE)
    count = math.min(count, stored)
    local calls = {}
    for offset = count - 1, 0, -1 do
        local index = (log.Head - offset - 1) % MAX_CALLS_PER_REMOTE + 1
        table.insert(calls, log.Calls[index])
    end
    return calls
end

function RemoteSpy:CallMeta()
    local checkcaller = self.Lookup("checkcaller")
    local getcallingscript = self.Lookup("getcallingscript")
    local isExecutor = false
    if type(checkcaller) == "function" then
        local ok, result = pcall(checkcaller)
        isExecutor = ok and result == true
    end
    local script
    if type(getcallingscript) == "function" then
        local ok, result = pcall(getcallingscript)
        if ok and self.TypeOf(result) == "Instance" then script = result end
    end
    return { IsExecutor = isExecutor, Script = script }
end

-- Shared by every outgoing hook. Returns true when the call must be dropped.
function RemoteSpy:InterceptOutgoing(instance, method, ...)
    if not self.Enabled or not self:IsTarget(instance, method) then return false end
    local meta = self:CallMeta()
    -- Never log or block the executor's own calls unless asked, so replays still go through.
    if meta.IsExecutor and not self.IncludeExecutorCalls then return false end
    return self:Record(instance, "Outgoing", method, table.pack(...), meta)
end

function RemoteSpy:InstallNamecallHook()
    local getnamecallmethod = self.Lookup("getnamecallmethod")
    if type(getnamecallmethod) ~= "function" then
        table.insert(self.Notes, "getnamecallmethod is missing, so remote:FireServer() calls cannot be intercepted through __namecall.")
        return false
    end
    local newcclosure = self.Lookup("newcclosure")
    if type(newcclosure) ~= "function" then newcclosure = identity end
    local spy = self
    local original

    local function handler(instance, ...)
        local method = getnamecallmethod()
        if not HOOKED_METHOD_NAMES[method] or not spy.Enabled then
            return original(instance, ...)
        end
        if spy:InterceptOutgoing(instance, method, ...) then
            return nil
        end
        -- Mark the thread so the function hooks below skip the same call.
        local thread = coroutine.running()
        spy.InNamecall[thread] = true
        local results = table.pack(original(instance, ...))
        spy.InNamecall[thread] = nil
        return table.unpack(results, 1, results.n)
    end

    local hookmetamethod = self.Lookup("hookmetamethod")
    if type(hookmetamethod) == "function" then
        local ok, result = pcall(hookmetamethod, self.Game, "__namecall", newcclosure(handler))
        if ok and type(result) == "function" then
            original = result
            self.OutgoingMode = "namecall-hook"
            return true
        end
        table.insert(self.Notes, "hookmetamethod failed: " .. tostring(result))
    end

    local getrawmetatable = self.Lookup("getrawmetatable")
    if type(getrawmetatable) == "function" then
        local ok, err = pcall(function()
            local metatable = getrawmetatable(self.Game)
            local setreadonly = self.Lookup("setreadonly")
            local makeWriteable = self.Lookup("make_writeable")
            original = metatable.__namecall
            assert(type(original) == "function", "game has no __namecall")
            if type(setreadonly) == "function" then
                setreadonly(metatable, false)
            elseif type(makeWriteable) == "function" then
                makeWriteable(metatable)
            end
            metatable.__namecall = newcclosure(handler)
            if type(setreadonly) == "function" then pcall(setreadonly, metatable, true) end
        end)
        if ok then
            self.OutgoingMode = "metatable"
            return true
        end
        table.insert(self.Notes, "raw metatable namecall swap failed: " .. tostring(err))
    end
    return false
end

function RemoteSpy:InstallFunctionHooks()
    local hookfunction = self.Lookup("hookfunction") or self.Lookup("replaceclosure") or self.Lookup("detour_function")
    if type(hookfunction) ~= "function" then
        table.insert(self.Notes, "hookfunction is missing, so direct remote.FireServer(remote) calls are not intercepted.")
        return false
    end
    local newcclosure = self.Lookup("newcclosure")
    if type(newcclosure) ~= "function" then newcclosure = identity end
    local spy = self
    local hooked = {}

    for class, method in OUTGOING_METHODS do
        local okFn, fn = pcall(function()
            return self.InstanceNew(class)[method]
        end)
        if not okFn or type(fn) ~= "function" or hooked[fn] then continue end
        hooked[fn] = true

        local original
        local okHook, result = pcall(hookfunction, fn, newcclosure(function(instance, ...)
            if spy.Enabled and not spy.InNamecall[coroutine.running()] then
                if spy:InterceptOutgoing(instance, method, ...) then
                    return nil
                end
            end
            return original(instance, ...)
        end))
        if okHook and type(result) == "function" then
            original = result
            self.FunctionHooks += 1
        else
            table.insert(self.Notes, "hookfunction failed on " .. class .. "." .. method .. ": " .. tostring(result))
        end
    end
    return self.FunctionHooks > 0
end

function RemoteSpy:ApplyIncomingBlock(instance)
    local watch = self.Watched[instance]
    local getconnections = self.Lookup("getconnections")
    if not watch or type(getconnections) ~= "function" then return false end
    local name = self:SafeIndex(instance, "Name") or "?"
    local shouldBlock = self.BlockRules.Incoming[name] == true
    local ok = pcall(function()
        for _, connection in getconnections(instance.OnClientEvent) do
            if connection.Function == watch.Handler then continue end
            if shouldBlock then
                connection:Disable()
            else
                connection:Enable()
            end
        end
    end)
    return ok
end

function RemoteSpy:Watch(instance)
    if self.Watched[instance] then return end
    local class = self:SafeIndex(instance, "ClassName")
    if not INCOMING_CLASSES[class] then return end

    local spy = self
    local watch = {}
    watch.Handler = function(...)
        if spy:Record(instance, "Incoming", "OnClientEvent", table.pack(...), nil) then
            -- Re-apply in case the game connected new handlers since the block.
            spy:ApplyIncomingBlock(instance)
        end
    end
    local ok, connection = pcall(function()
        return instance.OnClientEvent:Connect(watch.Handler)
    end)
    if not ok then return end
    watch.Connection = connection
    self.Watched[instance] = watch
    self.WatchedCount += 1
    if self.BlockRules.Incoming[self:SafeIndex(instance, "Name") or "?"] then
        self:ApplyIncomingBlock(instance)
    end
end

function RemoteSpy:InstallIncoming()
    local spy = self
    local okConnect = pcall(function()
        self.DescendantConnection = self.Game.DescendantAdded:Connect(function(instance)
            spy:Watch(instance)
        end)
    end)
    local okScan = pcall(function()
        for _, instance in self.Game:GetDescendants() do
            spy:Watch(instance)
        end
    end)
    local getnilinstances = self.Lookup("getnilinstances")
    if type(getnilinstances) == "function" then
        pcall(function()
            for _, instance in getnilinstances() do
                spy:Watch(instance)
            end
        end)
    end
    if okConnect or okScan then
        self.IncomingMode = "connections"
        return true
    end
    table.insert(self.Notes, "Could not scan the game for RemoteEvents.")
    return false
end

function RemoteSpy:Start()
    if self.Started then return self end
    self.Started = true
    local namecall = self:InstallNamecallHook()
    local functions = self:InstallFunctionHooks()
    if not namecall and functions then
        self.OutgoingMode = "function-hook"
    end
    self:InstallIncoming()
    return self
end

-- Rules apply by exact name, including remotes that have not fired yet.
function RemoteSpy:SetRule(kind, direction, name, value)
    local rules = (kind == "block" and self.BlockRules or self.IgnoreRules)[direction]
    assert(rules, "Invalid direction: " .. tostring(direction) .. " (use Incoming or Outgoing)")
    assert(type(name) == "string" and name ~= "", "remoteName is required")
    rules[name] = value or nil

    local matched = 0
    for instance, log in self.Logs[direction] do
        if log.Name == name then matched += 1 end
    end
    local applied = true
    if kind == "block" and direction == "Incoming" then
        for instance in self.Watched do
            if self:SafeIndex(instance, "Name") == name then
                applied = self:ApplyIncomingBlock(instance) and applied
            end
        end
    end
    return matched, applied
end

function RemoteSpy:Clear()
    self.Logs = newDirectionTable()
    self.RemoteCounts = { Outgoing = 0, Incoming = 0 }
end

local function formatIndex(name)
    if string.match(name, "^[%a_][%w_]*$") then
        return "." .. name
    end
    return "[" .. string.format("%q", name) .. "]"
end

function RemoteSpy:PathOf(instance)
    local parts = {}
    local current = instance
    for _ = 1, 200 do
        local parent = self:SafeIndex(current, "Parent")
        if parent == nil then
            return nil
        end
        if parent == self.Game then
            local class = self:SafeIndex(current, "ClassName") or "Workspace"
            table.insert(parts, 1, string.format("game:GetService(%q)", class))
            return table.concat(parts)
        end
        table.insert(parts, 1, formatIndex(self:SafeIndex(current, "Name") or "?"))
        current = parent
    end
    return nil
end

function RemoteSpy:ReplayFor(log, call)
    local path = self:PathOf(log.Instance)
    if not path then
        return "-- " .. log.Name .. " is parented to nil; find it with getnilinstances() first."
    end
    local args = call.Arguments
    local array = {}
    for i = 1, args.n or #args do
        array[i] = args[i]
    end
    local encodedOk, encoded = pcall(self.Encode, array, { Prettify = false })
    if not encodedOk then
        encoded = "{} -- arguments could not be serialized: " .. tostring(encoded)
    end
    local count = args.n or #args
    if log.Direction == "Incoming" then
        return string.format(
            "local args = %s\nfiresignal(%s.OnClientEvent, table.unpack(args, 1, %d))",
            encoded, path, count
        )
    end
    return string.format(
        "local args = %s\n%s:%s(table.unpack(args, 1, %d))",
        encoded, path, log.Method, count
    )
end

function RemoteSpy:Status()
    local getconnections = self.Lookup("getconnections")
    local outgoingRules, incomingRules = {}, {}
    for name in self.BlockRules.Outgoing do table.insert(outgoingRules, "block " .. name) end
    for name in self.IgnoreRules.Outgoing do table.insert(outgoingRules, "ignore " .. name) end
    for name in self.BlockRules.Incoming do table.insert(incomingRules, "block " .. name) end
    for name in self.IgnoreRules.Incoming do table.insert(incomingRules, "ignore " .. name) end
    return {
        status = "running",
        enabled = self.Enabled,
        outgoing = self.OutgoingMode,
        outgoingFunctionHooks = self.FunctionHooks,
        outgoingBlocking = self.OutgoingMode ~= "unavailable",
        incoming = self.IncomingMode,
        incomingBlocking = type(getconnections) == "function",
        remoteEventsWatched = self.WatchedCount,
        outgoingRemotes = self.RemoteCounts.Outgoing,
        incomingRemotes = self.RemoteCounts.Incoming,
        includeBindables = self.IncludeBindables,
        includeExecutorCalls = self.IncludeExecutorCalls,
        outgoingRules = outgoingRules,
        incomingRules = incomingRules,
        notes = self.Notes,
    }
end

function RemoteSpy:List(options)
    local direction = options.direction or "Both"
    local filter = string.lower(options.nameFilter or "")
    local limit = math.clamp(math.floor(tonumber(options.limit) or 10), 1, 100)
    local callsPerRemote = math.clamp(math.floor(tonumber(options.maxCallsPerRemote) or 2), 0, 20)
    local summaryOnly = options.summaryOnly == true

    local entries = {}
    for _, dir in { "Outgoing", "Incoming" } do
        if direction ~= "Both" and direction ~= dir then continue end
        for _, log in self.Logs[dir] do
            if filter ~= "" and not string.find(string.lower(log.Name), filter, 1, true) then continue end
            table.insert(entries, log)
        end
    end
    table.sort(entries, function(a, b)
        if a.TotalCalls ~= b.TotalCalls then return a.TotalCalls > b.TotalCalls end
        return a.Name < b.Name
    end)

    local results = {}
    for i = 1, math.min(limit, #entries) do
        local log = entries[i]
        local entry = {
            RemoteName = log.Name,
            RemoteClass = log.ClassName,
            Path = self:PathOf(log.Instance),
            Direction = log.Direction,
            Method = log.Method,
            TotalCalls = log.TotalCalls,
            Blocked = self.BlockRules[log.Direction][log.Name] == true,
            Ignored = self.IgnoreRules[log.Direction][log.Name] == true,
        }
        if not summaryOnly and callsPerRemote > 0 then
            local calls = {}
            for _, call in self:RecentCalls(log, callsPerRemote) do
                local array = {}
                for index = 1, call.Arguments.n or #call.Arguments do
                    array[index] = call.Arguments[index]
                end
                table.insert(calls, {
                    Number = call.Number,
                    Arguments = array,
                    ArgumentCount = call.Arguments.n,
                    Script = call.Script and (self:PathOf(call.Script) or self:SafeIndex(call.Script, "Name")) or nil,
                    IsExecutor = call.IsExecutor,
                    Blocked = call.Blocked,
                    SecondsAgo = math.floor((self.Clock() - call.Time) * 10) / 10,
                    Replay = self:ReplayFor(log, call),
                })
            end
            entry.RecentCalls = calls
        end
        table.insert(results, entry)
    end
    return { count = #results, totalMatching = #entries, results = results }
end

-- One spy per Roblox session. It lives in the executor environment so hooks are not
-- installed twice when the bridge reconnects or the connector is re-run.
function RemoteSpy.Get(context)
    local environment = context.Environment
    local existing = environment.MCP_RemoteSpy
    if type(existing) == "table" and type(existing.List) == "function" then
        return existing
    end
    local spy = RemoteSpy.new({
        Lookup = context.Compatibility.Lookup,
        Game = game,
        InstanceNew = Instance.new,
        LuaEncode = context.LuaEncode,
    })
    spy:Start()
    environment.MCP_RemoteSpy = spy
    return spy
end

return RemoteSpy
