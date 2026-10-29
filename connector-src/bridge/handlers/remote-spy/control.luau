return function(context, Bridge)
local Environment = context.Environment
    Bridge:BindToType("clear-remote-spy-logs", function(data)
        local Cobalt = Environment.Cobalt
        assert(Cobalt and Cobalt.shared and Cobalt.shared.ClearLogs, "Cobalt remote spy is not loaded. Call ensure-remote-spy first.")

        Cobalt.shared.ClearLogs()

        return {
            status = "cleared",
            message = "All remote spy logs have been cleared."
        }
    end)

    Bridge:BindToType("block-remote", function(data)
        local Cobalt = Environment.Cobalt
        assert(Cobalt and Cobalt.shared and Cobalt.shared.Logs, "Cobalt remote spy is not loaded. Call ensure-remote-spy first.")

        local remoteName = data.remoteName
        local direction = data.direction
        local shouldBlock = data.shouldBlock

        local logTable = Cobalt.shared.Logs[direction]
        assert(logTable, "Invalid direction: " .. tostring(direction))

        for instance, log in logTable do
            if typeof(instance) ~= "Instance" then continue end

            local name = ""
            pcall(function() name = instance.Name end)

            if name == remoteName then
                if shouldBlock and not log.Blocked then
                    log:Block()
                elseif not shouldBlock and log.Blocked then
                    log:Block() -- toggles
                end

                return {
                    status = "success",
                    message = (shouldBlock and "Blocked" or "Unblocked") .. " remote: " .. remoteName,
                    blocked = log.Blocked
                }
            end
        end

        error("Remote not found: " .. remoteName .. " in " .. direction .. " logs. Make sure the remote has been logged at least once.")
    end)

    Bridge:BindToType("ignore-remote", function(data)
        local Cobalt = Environment.Cobalt
        assert(Cobalt and Cobalt.shared and Cobalt.shared.Logs, "Cobalt remote spy is not loaded. Call ensure-remote-spy first.")

        local remoteName = data.remoteName
        local direction = data.direction
        local shouldIgnore = data.shouldIgnore

        local logTable = Cobalt.shared.Logs[direction]
        assert(logTable, "Invalid direction: " .. tostring(direction))

        for instance, log in logTable do
            if typeof(instance) ~= "Instance" then continue end

            local name = ""
            pcall(function() name = instance.Name end)

            if name == remoteName then
                if shouldIgnore and not log.Ignored then
                    log:Ignore()
                elseif not shouldIgnore and log.Ignored then
                    log:Ignore() -- toggles
                end

                return {
                    status = "success",
                    message = (shouldIgnore and "Ignoring" or "Unignored") .. " remote: " .. remoteName,
                    ignored = log.Ignored
                }
            end
        end

        error("Remote not found: " .. remoteName .. " in " .. direction .. " logs. Make sure the remote has been logged at least once.")
    end)

    -- Keep Cobalt's implementation details behind one public MCP operation.
    -- The legacy callbacks above remain internal so this dispatcher can reuse
    -- their validated filtering and state-change behavior.
    Bridge:BindToType("remote-spy", function(data)
        Bridge.Callbacks["ensure-remote-spy"]({})

        local operation = data.operation
        if operation == "status" then
            local Cobalt = Environment.Cobalt
            local function CountLogs(logTable)
                local count = 0
                if typeof(logTable) ~= "table" then return count end
                for _ in logTable do
                    count += 1
                end
                return count
            end

            return {
                status = "loaded",
                outgoingRemotes = CountLogs(Cobalt.shared and Cobalt.shared.Logs and Cobalt.shared.Logs.Outgoing),
                incomingRemotes = CountLogs(Cobalt.shared and Cobalt.shared.Logs and Cobalt.shared.Logs.Incoming),
            }
        elseif operation == "list" then
            return Bridge.Callbacks["get-remote-spy-logs"]({
                direction = data.direction,
                remoteNameFilter = data.nameFilter,
                limit = data.limit,
                maxCallsPerRemote = data.maxCallsPerRemote,
                summaryOnly = data.summaryOnly,
            })
        elseif operation == "clear" then
            return Bridge.Callbacks["clear-remote-spy-logs"]({})
        elseif operation == "block" or operation == "unblock" then
            return Bridge.Callbacks["block-remote"]({
                remoteName = data.remoteName,
                direction = data.direction,
                shouldBlock = operation == "block",
            })
        elseif operation == "ignore" or operation == "unignore" then
            return Bridge.Callbacks["ignore-remote"]({
                remoteName = data.remoteName,
                direction = data.direction,
                shouldIgnore = operation == "ignore",
            })
        end

        error("Invalid remote-spy operation: " .. tostring(operation))
    end)
end
