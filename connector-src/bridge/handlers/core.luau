return function(context, Bridge)
local LogService = context.LogService
local Compatibility = context.Compatibility

    Bridge:BindToType("execute", function(data)
        task.defer(function()
            Compatibility.SetThreadIdentity(data.threadContext or 8)
            local chunk, compileError = loadstring(data.source)
            assert(chunk, compileError)
            chunk()
        end)
    end)

    Bridge:BindToTypeRaw("get-console-output", function(data)
        local limit = math.max(1, math.min(tonumber(data.limit) or 20, 200))
        local logsOrder = data.logsOrder or "NewestFirst"
        local filter = data.filter
        local hasFilter = typeof(filter) == "string" and filter ~= ""
        local summaryOnly = data.summaryOnly == true

        local logs = LogService:GetLogHistory()
        local results = {}
        local matchedCount = 0
        local countsByLevel = {}

        local function matchesFilter(logEntry)
            if not hasFilter then return true end
            return string.find(logEntry.message, filter, 1, true) ~= nil
        end

        local MAX_LOG_MESSAGE_CHARS = 500
        local function formatLogMessage(message)
            local output = tostring(message or "")
            if #output > MAX_LOG_MESSAGE_CHARS then
                output = string.sub(output, 1, MAX_LOG_MESSAGE_CHARS)
                    .. "…(+" .. (#output - MAX_LOG_MESSAGE_CHARS) .. " chars omitted)"
            end
            return output
        end

        if logsOrder == "NewestFirst" then
            for i = #logs, 1, -1 do
                local logEntry = logs[i]
                if not matchesFilter(logEntry) then continue end
                
                matchedCount += 1
                local levelName = logEntry.messageType and logEntry.messageType.Name or "Unknown"
                countsByLevel[levelName] = (countsByLevel[levelName] or 0) + 1
                if #results < limit then
                    table.insert(results, logEntry)
                end
            end
        else
            for _, logEntry in logs do
                if not matchesFilter(logEntry) then continue end
                
                matchedCount += 1
                local levelName = logEntry.messageType and logEntry.messageType.Name or "Unknown"
                countsByLevel[levelName] = (countsByLevel[levelName] or 0) + 1
                if #results < limit then
                    table.insert(results, logEntry)
                end
            end
        end

        local outputLines = {}
        if summaryOnly then
            table.insert(outputLines, string.format("Matched %d logs.", matchedCount))
            for levelName, count in countsByLevel do
                table.insert(outputLines, string.format("%s: %d", levelName, count))
            end
            return table.concat(outputLines, "\n")
        end

        table.insert(outputLines, string.format("Displaying %d/%d logs:", #results, matchedCount))

        for _, logEntry in results do
            table.insert(outputLines, string.format(
                "[%s t=%s] %s",
                logEntry.messageType.Name, tostring(logEntry.timestamp),
                formatLogMessage(logEntry.message)
            ))
        end

        return table.concat(outputLines, "\n")
    end)

    Bridge:BindToType("get-data-by-code", function(data)
        Compatibility.SetThreadIdentity(data.threadContext or 8)
        local chunk, compileError = loadstring(data.source)
        assert(chunk, compileError)
        local dataOutput = table.pack(chunk())

        return dataOutput
    end)
end
