local RemoteSpy = require("../../../remote-spy/spy")

return function(context, Bridge)
    local function SetRule(kind, data, value)
        local spy = RemoteSpy.Get(context)
        local matched, applied = spy:SetRule(kind, data.direction, data.remoteName, value)
        local verb = if kind == "block"
            then (value and "Blocked" or "Unblocked")
            else (value and "Ignoring" or "Unignored")
        local result = {
            status = "success",
            message = string.format("%s %s remote %q. Matches %d logged remote(s); the rule also applies to remotes that have not fired yet.",
                verb, data.direction, data.remoteName, matched),
            matchedRemotes = matched,
        }
        if kind == "block" and data.direction == "Outgoing" and spy.OutgoingMode == "unavailable" then
            result.warning = "Outgoing calls cannot be intercepted on this executor, so this block has no effect."
        elseif kind == "block" and data.direction == "Incoming" and not applied then
            result.warning = "Blocking incoming events needs getconnections, which this executor lacks. Events are still logged."
        end
        return result
    end

    Bridge:BindToType("clear-remote-spy-logs", function()
        RemoteSpy.Get(context):Clear()
        return { status = "cleared", message = "All remote spy logs have been cleared. Block and ignore rules are kept." }
    end)

    Bridge:BindToType("block-remote", function(data)
        return SetRule("block", data, data.shouldBlock ~= false)
    end)

    Bridge:BindToType("ignore-remote", function(data)
        return SetRule("ignore", data, data.shouldIgnore ~= false)
    end)

    Bridge:BindToType("remote-spy", function(data)
        local spy = RemoteSpy.Get(context)
        local operation = data.operation

        if operation == "status" then
            return spy:Status()
        elseif operation == "list" then
            return spy:List(data)
        elseif operation == "clear" then
            spy:Clear()
            return { status = "cleared", message = "All remote spy logs have been cleared. Block and ignore rules are kept." }
        elseif operation == "block" or operation == "unblock" then
            return SetRule("block", data, operation == "block")
        elseif operation == "ignore" or operation == "unignore" then
            return SetRule("ignore", data, operation == "ignore")
        elseif operation == "configure" then
            if data.enabled ~= nil then spy.Enabled = data.enabled == true end
            if data.includeBindables ~= nil then spy.IncludeBindables = data.includeBindables == true end
            if data.includeExecutorCalls ~= nil then spy.IncludeExecutorCalls = data.includeExecutorCalls == true end
            return spy:Status()
        end

        error("Invalid remote-spy operation: " .. tostring(operation))
    end)
end
