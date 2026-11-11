local RemoteSpy = require("../connector-src/remote-spy/spy")

--// Fake instance world \\--
local function NewSignal()
    local signal = { connections = {} }
    function signal:Connect(callback)
        local connection = { callback = callback, disabled = false }
        function connection:Disconnect() self.callback = nil end
        table.insert(self.connections, connection)
        return connection
    end
    function signal:Fire(...)
        for _, connection in self.connections do
            if connection.callback and not connection.disabled then connection.callback(...) end
        end
    end
    return signal
end

local function NewWorld()
    local world = { descendants = {} }
    local game = { ClassName = "DataModel", Name = "Game", DescendantAdded = NewSignal() }
    function game:GetDescendants() return world.descendants end
    world.game = game
    function world.add(class, name, parent)
        local instance = { ClassName = class, Name = name, Parent = parent }
        if class == "RemoteEvent" or class == "UnreliableRemoteEvent" then
            instance.OnClientEvent = NewSignal()
        end
        table.insert(world.descendants, instance)
        return instance
    end
    local storage = world.add("ReplicatedStorage", "ReplicatedStorage", game)
    local folder = world.add("Folder", "Remotes", storage)
    world.buy = world.add("RemoteEvent", "Buy", folder)
    world.sell = world.add("RemoteEvent", "Sell", folder)
    world.weird = world.add("RemoteEvent", "Weird Name", folder)
    world.getData = world.add("RemoteFunction", "GetData", folder)
    world.bindable = world.add("BindableEvent", "LocalSignal", folder)
    world.script = world.add("LocalScript", "Client", storage)
    return world
end

local function TypeOf(value)
    if type(value) == "table" and value.ClassName then return "Instance" end
    return type(value)
end

local function Encode(value)
    local parts = {}
    for i, item in value do
        parts[#parts + 1] = "[" .. i .. "]=" .. (type(item) == "string" and string.format("%q", item) or tostring(item))
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

--// Fake executor \\--
-- Real C functions for each remote method. `active` holds whatever hookfunction installed.
local function NewExecutor(world, features)
    local executor = { fired = {}, active = {}, method = nil, isExecutor = false }
    local realFunctions = {}
    for _, method in { "FireServer", "InvokeServer", "Fire", "Invoke" } do
        local fn
        fn = function(instance, ...)
            table.insert(executor.fired, { instance = instance, method = method, n = select("#", ...) })
            return "result"
        end
        realFunctions[method] = fn
        executor.active[fn] = fn
    end
    local classMethod = {
        RemoteEvent = "FireServer", UnreliableRemoteEvent = "FireServer", RemoteFunction = "InvokeServer",
        BindableEvent = "Fire", BindableFunction = "Invoke",
    }
    executor.realFunctions = realFunctions

    -- Like Roblox: the C __namecall dispatches to the (possibly hooked) method function.
    local function originalNamecall(instance, ...)
        local fn = realFunctions[executor.method]
        if fn then return executor.active[fn](instance, ...) end
        return nil
    end
    local metatable = { __namecall = originalNamecall }
    executor.metatable = metatable

    local api = {}
    if features.namecall then
        api.getnamecallmethod = function() return executor.method end
    end
    if features.hookmetamethod then
        api.hookmetamethod = function(target, name, hook)
            assert(target == world.game and name == "__namecall")
            local original = metatable.__namecall
            metatable.__namecall = hook
            return original
        end
    end
    if features.rawmetatable then
        api.getrawmetatable = function() return metatable end
        api.setreadonly = function(target, readonly) executor.readonly = readonly end
    end
    if features.hookfunction then
        api.hookfunction = function(fn, hook)
            local original = executor.active[fn]
            executor.active[fn] = hook
            return original
        end
    end
    if features.checkcaller then
        api.checkcaller = function() return executor.isExecutor end
        api.getcallingscript = function() return world.script end
    end
    if features.getconnections then
        api.getconnections = function(signal)
            local list = {}
            for _, connection in signal.connections do
                -- Like Athena: disabled connections are not listed.
                if connection.disabled or not connection.callback then continue end
                table.insert(list, {
                    Function = connection.callback,
                    Disable = function() connection.disabled = true end,
                    Enable = function() connection.disabled = false end,
                })
            end
            return list
        end
    end
    api.newcclosure = function(fn) return fn end

    function executor.namecall(instance, method, ...)
        executor.method = method
        return metatable.__namecall(instance, ...)
    end
    function executor.direct(instance, ...)
        local fn = realFunctions[classMethod[instance.ClassName]]
        return executor.active[fn](instance, ...)
    end
    function executor.lookup(name) return api[name] end
    function executor.instanceNew(class)
        return { [classMethod[class]] = realFunctions[classMethod[class]] }
    end
    return executor
end

local function NewSpy(world, executor)
    local now = 0
    local spy = RemoteSpy.new({
        Lookup = executor.lookup,
        Game = world.game,
        InstanceNew = executor.instanceNew,
        TypeOf = TypeOf,
        Clock = function() now += 1 return now end,
        LuaEncode = Encode,
    })
    return spy:Start()
end

local FULL = { namecall = true, hookmetamethod = true, hookfunction = true, checkcaller = true, getconnections = true }

--// Full executor \\--
do
    local world = NewWorld()
    local executor = NewExecutor(world, FULL)
    local spy = NewSpy(world, executor)
    local status = spy:Status()
    assert(status.outgoing == "namecall-hook", "full executor uses the namecall hook")
    assert(status.outgoingFunctionHooks == 4, "one function hook per distinct method")
    assert(status.incoming == "connections" and status.remoteEventsWatched == 3)
    assert(status.incomingBlocking == true)

    -- The namecall goes through the hooked FireServer too; it must be logged once.
    assert(executor.namecall(world.buy, "FireServer", 1, "x", nil) == "result")
    local log = spy.Logs.Outgoing[world.buy]
    assert(log and log.TotalCalls == 1, "namecall plus function hook must log a single call")
    assert(#executor.fired == 1 and executor.fired[1].n == 3, "call still reaches the server with all arguments")
    assert(log.Calls[1].Script == world.script, "calling script is captured")

    -- Direct calls bypass __namecall and are caught by hookfunction.
    executor.direct(world.buy, 5)
    assert(log.TotalCalls == 2, "direct FireServer calls are logged")

    -- Rules apply before a remote first fires.
    spy:SetRule("block", "Outgoing", "Sell", true)
    local firedBefore = #executor.fired
    assert(executor.namecall(world.sell, "FireServer", "item") == nil, "blocked call returns nothing")
    assert(#executor.fired == firedBefore, "blocked call never reaches the server")
    assert(spy.Logs.Outgoing[world.sell].Calls[1].Blocked == true, "blocked calls are still logged")
    spy:SetRule("block", "Outgoing", "Sell", false)
    executor.namecall(world.sell, "FireServer", "item")
    assert(#executor.fired == firedBefore + 1, "unblock lets calls through again")

    -- Ignore stops logging but not the call.
    spy:SetRule("ignore", "Outgoing", "Buy", true)
    executor.namecall(world.buy, "FireServer", 9)
    assert(log.TotalCalls == 2, "ignored remote is not logged")
    spy:SetRule("ignore", "Outgoing", "Buy", false)

    -- Executor calls pass untouched by default, even when blocked.
    spy:SetRule("block", "Outgoing", "Buy", true)
    executor.isExecutor = true
    firedBefore = #executor.fired
    executor.namecall(world.buy, "FireServer", "replay")
    assert(#executor.fired == firedBefore + 1 and log.TotalCalls == 2, "executor calls skip logging and blocking")
    executor.isExecutor = false
    spy:SetRule("block", "Outgoing", "Buy", false)

    -- InvokeServer and unrelated namecalls.
    assert(executor.namecall(world.getData, "InvokeServer", "key") == "result")
    assert(spy.Logs.Outgoing[world.getData].Method == "InvokeServer")
    executor.namecall(world.buy, "GetFullName")
    executor.namecall(world.buy, "InvokeServer")
    assert(log.TotalCalls == 2, "wrong method for the class is ignored")

    -- Bindables are off by default.
    executor.namecall(world.bindable, "Fire", 1)
    assert(spy.Logs.Outgoing[world.bindable] == nil, "bindables are skipped by default")
    spy.IncludeBindables = true
    executor.namecall(world.bindable, "Fire", 1)
    assert(spy.Logs.Outgoing[world.bindable].TotalCalls == 1, "bindables log when enabled")

    -- Paused spy passes everything through.
    spy.Enabled = false
    executor.namecall(world.buy, "FireServer", 1)
    assert(log.TotalCalls == 2)
    spy.Enabled = true

    -- Incoming logging and blocking.
    local gameHandlerCalls = 0
    world.buy.OnClientEvent:Connect(function() gameHandlerCalls += 1 end)
    world.buy.OnClientEvent:Fire("hello", 42)
    local incoming = spy.Logs.Incoming[world.buy]
    assert(incoming and incoming.TotalCalls == 1 and incoming.Calls[1].Arguments.n == 2)
    assert(gameHandlerCalls == 1)
    local _, applied = spy:SetRule("block", "Incoming", "Buy", true)
    assert(applied, "incoming block applies with getconnections")
    world.buy.OnClientEvent:Fire("blocked")
    assert(gameHandlerCalls == 1, "blocked incoming event never reaches game handlers")
    assert(incoming.TotalCalls == 2, "blocked incoming event is still logged")
    spy:SetRule("block", "Incoming", "Buy", false)
    world.buy.OnClientEvent:Fire("again")
    assert(gameHandlerCalls == 2, "unblocking re-enables game handlers")

    -- New remotes are watched as they appear.
    local late = world.add("UnreliableRemoteEvent", "Late", world.game)
    world.game.DescendantAdded:Fire(late)
    late.OnClientEvent:Fire(1)
    assert(spy.Logs.Incoming[late].TotalCalls == 1, "remotes added later are watched")

    -- Listing, paths and replay snippets.
    local listed = spy:List({ direction = "Outgoing", nameFilter = "buy", limit = 5, maxCallsPerRemote = 5, summaryOnly = false })
    assert(listed.count == 1)
    local entry = listed.results[1]
    assert(entry.Path == 'game:GetService("ReplicatedStorage").Remotes.Buy', "path: " .. tostring(entry.Path))
    assert(#entry.RecentCalls == 2 and entry.RecentCalls[1].Number == 1, "recent calls are oldest first")
    assert(string.find(entry.RecentCalls[1].Replay, ".Remotes.Buy:FireServer(table.unpack(args, 1, 3))", 1, true), entry.RecentCalls[1].Replay)
    executor.namecall(world.weird, "FireServer")
    local weird = spy:List({ nameFilter = "weird", summaryOnly = false, maxCallsPerRemote = 1 }).results[1]
    assert(weird.Path == 'game:GetService("ReplicatedStorage").Remotes["Weird Name"]', weird.Path)
    local incomingReplay = spy:List({ direction = "Incoming", nameFilter = "buy", summaryOnly = false }).results[1].RecentCalls[1].Replay
    assert(string.find(incomingReplay, "firesignal(", 1, true), "incoming replay uses firesignal")
    local summary = spy:List({ summaryOnly = true }).results[1]
    assert(summary.RecentCalls == nil, "summaryOnly omits calls")

    -- Ring buffer keeps the newest calls.
    for i = 1, 60 do executor.namecall(world.sell, "FireServer", i) end
    local sellLog = spy.Logs.Outgoing[world.sell]
    local recent = spy:RecentCalls(sellLog, 100)
    assert(#recent == 50 and recent[#recent].Number == sellLog.TotalCalls and recent[1].Number == sellLog.TotalCalls - 49)

    spy:Clear()
    assert(next(spy.Logs.Outgoing) == nil and spy.RemoteCounts.Outgoing == 0, "clear empties logs")
end

--// Raw metatable fallback \\--
do
    local world = NewWorld()
    local executor = NewExecutor(world, { namecall = true, rawmetatable = true })
    local spy = NewSpy(world, executor)
    assert(spy.OutgoingMode == "metatable", "falls back to the raw metatable")
    assert(executor.readonly == true, "metatable is made read-only again")
    executor.namecall(world.buy, "FireServer", 1)
    assert(spy.Logs.Outgoing[world.buy].TotalCalls == 1)
    spy:SetRule("block", "Outgoing", "Buy", true)
    local before = #executor.fired
    executor.namecall(world.buy, "FireServer", 2)
    assert(#executor.fired == before, "metatable mode can block")
    assert(spy:Status().incomingBlocking == false)
end

--// hookfunction only \\--
do
    local world = NewWorld()
    local executor = NewExecutor(world, { hookfunction = true })
    local spy = NewSpy(world, executor)
    assert(spy.OutgoingMode == "function-hook", "uses function hooks without getnamecallmethod")
    executor.namecall(world.buy, "FireServer", 1)
    executor.direct(world.buy, 2)
    assert(spy.Logs.Outgoing[world.buy].TotalCalls == 2, "function hooks catch namecall and direct calls")
end

--// Weak executor: no hooks at all \\--
do
    local world = NewWorld()
    local executor = NewExecutor(world, {})
    local spy = NewSpy(world, executor)
    local status = spy:Status()
    assert(status.outgoing == "unavailable" and status.outgoingBlocking == false)
    assert(status.incoming == "connections", "incoming logging works without executor APIs")
    assert(#status.notes >= 2, "notes explain what is missing")
    executor.namecall(world.buy, "FireServer", 1)
    assert(spy.Logs.Outgoing[world.buy] == nil)
    world.sell.OnClientEvent:Fire("from server")
    assert(spy.Logs.Incoming[world.sell].TotalCalls == 1, "incoming events are logged on weak executors")
    local _, applied = spy:SetRule("block", "Incoming", "Sell", true)
    assert(applied == false, "incoming block reports it could not apply")
end

print("remote spy tests passed")
