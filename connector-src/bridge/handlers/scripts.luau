return function(context, Bridge)
local ScriptMappingPipeline = context.ScriptMappingPipeline
local GetScriptByDebugId = context.GetScriptByDebugId
local DecompileScriptSource = context.DecompileScriptSource
local QueueMappedScriptSource = context.QueueMappedScriptSource

    Bridge:BindToTypeRaw("get-script-content", function(data)
        local source
        local scriptInstance

        --// Handle GC'd script proxies: debugId is passed directly, skip loadstring \\--
        if data.debugId then
            scriptInstance = GetScriptByDebugId(data.debugId)
            assert(scriptInstance, "No live script instance found for ScriptProxy with DebugId: " .. tostring(data.debugId))
        else
            context.Compatibility.SetThreadIdentity(8)
            scriptInstance = loadstring(data.source)()

            assert(typeof(scriptInstance) == "Instance", "Script instance is not an instance.")
            assert(scriptInstance:IsA("LuaSourceContainer"), "Script instance is not a LuaSourceContainer (Script, LocalScript, or ModuleScript).")
            assert(not (scriptInstance:IsA("Script") and scriptInstance.RunContext == Enum.RunContext.Server), "Script instance is a Server Script.")
        end

        local scriptHash
        source, _, scriptHash = DecompileScriptSource(
            scriptInstance,
            nil,
            ScriptMappingPipeline.generation,
            ScriptMappingPipeline.clientId
        )
        assert(source, "Failed to decompile script.")

        local debugId = scriptInstance:GetDebugId()
        local mappingJob = ScriptMappingPipeline.jobs[debugId]
        if ScriptMappingPipeline.clientId and (not mappingJob or mappingJob.state ~= "mapped") then
            QueueMappedScriptSource(
                scriptInstance,
                source,
                scriptHash,
                ScriptMappingPipeline.generation,
                debugId
            )
        end

        --// Line range support with bounded default preview \\--
        local lines = {}
        local pos = 1
        local len = #source
        while pos <= len do
            local newlinePos = source:find("\n", pos, true)
            if newlinePos then
                table.insert(lines, source:sub(pos, newlinePos - 1))
                pos = newlinePos + 1
            else
                table.insert(lines, source:sub(pos))
                break
            end
        end

        local totalLines = #lines
        local maxLines = math.max(1, math.min(tonumber(data.maxLines) or 200, 2000))
        local startLine = data.startLine and math.max(1, math.min(data.startLine, totalLines)) or 1
        local requestedEndLine = data.endLine and math.max(startLine, math.min(data.endLine, totalLines)) or totalLines
        local endLine = math.min(requestedEndLine, startLine + maxLines - 1)

        local sliced = {}
        for i = startLine, endLine do
            table.insert(sliced, lines[i])
        end

        local footer = ""
        if endLine < requestedEndLine then
            footer = "\n-- Output truncated to " .. maxLines .. " lines. Rerun with startLine=" .. (endLine + 1) .. " or a tighter range to continue."
        end

        return "-- Lines " .. startLine .. "-" .. endLine .. " of " .. totalLines .. "\n" .. table.concat(sliced, "\n") .. footer
    end)
end
