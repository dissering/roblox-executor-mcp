local RemoteSpy = require("../../../remote-spy/spy")

return function(context, Bridge)
    Bridge:BindToType("ensure-remote-spy", function()
        local alreadyRunning = type(context.Environment.MCP_RemoteSpy) == "table"
        local spy = RemoteSpy.Get(context)
        local status = spy:Status()
        status.status = alreadyRunning and "already_running" or "started"
        return status
    end)

    Bridge:BindToType("get-remote-spy-logs", function(data)
        return RemoteSpy.Get(context):List({
            direction = data.direction,
            nameFilter = data.remoteNameFilter or data.nameFilter,
            limit = data.limit,
            maxCallsPerRemote = data.maxCallsPerRemote,
            summaryOnly = data.summaryOnly,
        })
    end)
end
