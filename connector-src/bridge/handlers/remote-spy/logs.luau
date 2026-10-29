return function(context, Bridge)
local Environment = context.Environment
    Bridge:BindToType("ensure-remote-spy", function(data)
        if Environment.Cobalt then
            return {
                status = "already_loaded",
                message = "Cobalt remote spy is already running."
            }
        end

        -- Load Cobalt
        context.Compatibility.RequireRemoteSpySupport()
        local success, err = pcall(function()
            loadstring(game:HttpGet("https://github.com/notpoiu/cobalt/releases/latest/download/Cobalt.luau"))()
        end)

        if not success then
            error("Failed to load Cobalt: " .. tostring(err))
        end

        -- Wait for Cobalt to initialize
        local waitStart = os.clock()
        while not Environment.Cobalt and os.clock() - waitStart < 10 do
            task.wait(0.1)
        end

        assert(Environment.Cobalt, "Cobalt loaded but failed to initialize within 10 seconds.")
        
        return {
            status = "loaded",
            message = "Cobalt remote spy loaded successfully."
        }
    end)

    Bridge:BindToType("get-remote-spy-logs", function(data)
        local Cobalt = Environment.Cobalt
        assert(Cobalt and Cobalt.shared and Cobalt.shared.Logs, "Cobalt remote spy is not loaded. Call ensure-remote-spy first.")

        local direction = data.direction or "Both"
        local nameFilter = data.remoteNameFilter or ""
        local limit = math.max(1, math.min(tonumber(data.limit) or 10, 100))
        local maxCallsPerRemote = math.max(0, math.min(tonumber(data.maxCallsPerRemote) or 2, 20))
        local summaryOnly = data.summaryOnly == true
        local hasNameFilter = nameFilter ~= ""

        local function ProcessLogs(logTable, directionLabel)
            local results = {}

            for instance, log in logTable do
                if typeof(instance) ~= "Instance" then continue end
                if #results >= limit then break end

                local remoteName = ""
                local remoteClass = ""
                pcall(function()
                    remoteName = instance.Name
                    remoteClass = instance.ClassName
                end)

                -- Apply name filter
                if hasNameFilter and not string.find(string.lower(remoteName), string.lower(nameFilter), 1, true) then
                    continue
                end

                -- Get recent calls (raw — LuaEncode handles serialization)
                local recentCalls = {}
                local totalCalls = #log.Calls
                local startIdx = math.max(1, totalCalls - maxCallsPerRemote + 1)

                if not summaryOnly then
                    for i = startIdx, totalCalls do
                        local call = log.Calls[i]
                        if not call then continue end

                        table.insert(recentCalls, {
                            Index = i,
                            Arguments = call.Arguments,
                            Origin = call.Origin,
                            IsExecutor = call.IsExecutor or false,
                            IsActor = call.IsActor or false,
                            Line = call.Line,
                        })
                    end
                end

                table.insert(results, {
                    RemoteName = remoteName,
                    RemoteClass = remoteClass,
                    Direction = directionLabel,
                    Method = log.Method,
                    TotalCalls = totalCalls,
                    Ignored = log.Ignored,
                    Blocked = log.Blocked,
                    RecentCalls = if summaryOnly then nil else recentCalls,
                })
            end

            return results
        end

        local allResults = {}

        if direction == "Outgoing" or direction == "Both" then
            local outgoing = ProcessLogs(Cobalt.shared.Logs.Outgoing, "Outgoing")
            for _, r in outgoing do
                table.insert(allResults, r)
            end
        end

        if direction == "Incoming" or direction == "Both" then
            local incoming = ProcessLogs(Cobalt.shared.Logs.Incoming, "Incoming")
            for _, r in incoming do
                table.insert(allResults, r)
            end
        end

        -- Sort by total calls descending (most active remotes first)
        table.sort(allResults, function(a, b)
            return a.TotalCalls > b.TotalCalls
        end)

        -- Trim to limit
        if #allResults > limit then
            local trimmed = {}
            for i = 1, limit do
                trimmed[i] = allResults[i]
            end
            allResults = trimmed
        end

        return {
            count = #allResults,
            results = allResults
        }
    end)
end
