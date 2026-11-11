local JobStatus = {}
JobStatus.__index = JobStatus
local emitWarning = warn or print
local DETAILED_FAILURES = 3
local SUMMARY_INTERVAL_SECONDS = 15

local function OneLine(message)
    local text = string.gsub(tostring(message or "unknown error"), "%s*\n+%s*", " | ")
    return text
end

function JobStatus.new(pipeline, failedResync)
    return setmetatable({
        pipeline = pipeline,
        failedResync = failedResync,
    }, JobStatus)
end

function JobStatus:Publish()
    self.pipeline.statusDirty = true
end

function JobStatus:MarkMapped(debugId, shouldPublish)
    local pipeline = self.pipeline
    local job = pipeline.jobs[debugId]
    if job and (job.state == "mapped" or job.state == "failed" or job.state == "removed") then
        return false
    end

    if not job then
        job = pipeline:EnsureJob(debugId)
    end

    pipeline:SetJobState(job, "mapped")
    if self.failedResync then self.failedResync:Cancel(job) end
    job.prepared = nil
    job.script = nil
    if shouldPublish ~= false then self:Publish() end
    return true
end

function JobStatus:MarkFailed(debugId, errorMessage, shouldPublish)
    local pipeline = self.pipeline
    local job = pipeline.jobs[debugId]
    if job and (job.state == "mapped" or job.state == "failed" or job.state == "removed") then
        return false
    end

    if not job then
        job = pipeline:EnsureJob(debugId)
    end

    pipeline:SetJobState(job, "failed")
    if self.failedResync then self.failedResync:Schedule(job) end
    job.errorMessage = tostring(errorMessage or "unknown error")
    job.prepared = nil
    job.script = nil
    self:ReportFailure(debugId, errorMessage)
    if shouldPublish ~= false then self:Publish() end
    return true
end

-- A big game can fail hundreds of scripts at once. Print the first few in full, then one
-- summary line per interval instead of a warning per script.
function JobStatus:ReportFailure(debugId, errorMessage)
    self.failureCount = (self.failureCount or 0) + 1
    if self.failureCount <= DETAILED_FAILURES then
        emitWarning("[roblox-mcp] could not index script " .. tostring(debugId) .. ": " .. OneLine(errorMessage))
        return
    end

    self.pendingFailures = (self.pendingFailures or 0) + 1
    self.lastFailure = OneLine(errorMessage)
    if self.summaryScheduled then return end
    self.summaryScheduled = true

    local function flush()
        self.summaryScheduled = false
        local count = self.pendingFailures or 0
        self.pendingFailures = 0
        if count > 0 then
            emitWarning(string.format(
                "[roblox-mcp] %d more scripts could not be indexed (%d total). Last error: %s",
                count, self.failureCount, tostring(self.lastFailure)
            ))
        end
    end
    if type(task) == "table" and type(task.delay) == "function" then
        task.delay(SUMMARY_INTERVAL_SECONDS, flush)
    else
        flush()
    end
end

return JobStatus
