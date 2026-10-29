return function(dependencies)
local request = dependencies.Request or request
local ScriptMappingPipeline = dependencies.ScriptMappingPipeline
local HttpService = dependencies.HttpService
local BridgeURL = dependencies.BridgeURL
local JobStatus = dependencies.JobStatus
local UploadBatchMax = 64
local UploadBatchMaxBytes = 8 * 1024 * 1024
local UploadFlushInterval = 0.5
local UploadMaxAttempts = 5
local UploadRetryMaxSeconds = 8

local function IsScriptMappingTransportReady(clientId)
    return (
        ScriptMappingPipeline.bridge ~= nil and
        ScriptMappingPipeline.bridge.Connected == true and
        ScriptMappingPipeline.bridge.ClientId ~= nil and
        ScriptMappingPipeline.bridge.ClientId == clientId
    )
end

local function UploadScriptSourceBatch(clientId, items)
    if not clientId then return false end
    if not IsScriptMappingTransportReady(clientId) then return false end
    local generation = ScriptMappingPipeline.generation
    local session = ScriptMappingPipeline.session
    if not session then return false end

    local scripts = {}
    local removedScriptIds = {}
    for _, item in items or {} do
        if item.kind == "remove" then
            table.insert(removedScriptIds, item.debugId)
        else
            table.insert(scripts, {
                debugId = item.debugId,
                path = item.path,
                source = item.source,
                scriptHash = item.scriptHash,
            })
        end
    end

    local scriptCount = #scripts
    local projectedProcessedSources = math.min(ScriptMappingPipeline.total, ScriptMappingPipeline.processed + scriptCount)
    local projectedFinished = ScriptMappingPipeline:IsFinished(projectedProcessedSources)
    local revision = session:NextRevision()

    local ok, response = pcall(request, {
        Url = "http://" .. BridgeURL .. "/script-sources",
        Method = "POST",
        Headers = {
            ["Content-Type"] = "application/json"
        },
        Body = HttpService:JSONEncode({
            clientId = clientId,
            scripts = scripts,
            removedScriptIds = removedScriptIds,
            hasFinishedMapping = projectedFinished,
            sourcesToMap = ScriptMappingPipeline.total,
            processedSources = projectedProcessedSources,
            skippedSources = ScriptMappingPipeline.skipped,
            mappingSessionId = session.id,
            mappingSessionStartedAt = session.startedAt,
            mappingRevision = revision,
            beginMappingSession = not session.started,
        })
    })

    if not ok or not response or response.StatusCode ~= 200 then return false, revision end

    if (
        not ScriptMappingPipeline:IsActiveSession(session, generation, clientId)
    ) then
        return false, revision, "stale_session"
    end

    local acceptedRevision = revision
    if type(response.Body) == "string" and response.Body ~= "" then
        local decodedOk, decoded = pcall(function()
            return HttpService:JSONDecode(response.Body)
        end)
        if decodedOk and type(decoded) == "table" and type(decoded.acceptedMappingRevision) == "number" then
            acceptedRevision = decoded.acceptedMappingRevision
        end
    end
    if acceptedRevision ~= revision then return false, revision end

    session:MarkStarted()
    return true, revision
end

local function EnqueueScriptSourceUpload(item)
    item.queuedBytes = if type(item.source) == "string" then #item.source else 0
    ScriptMappingPipeline.upload.tail += 1
    ScriptMappingPipeline.upload.queue[ScriptMappingPipeline.upload.tail] = item
    ScriptMappingPipeline.upload.bytes += item.queuedBytes
end

local function DequeueScriptSourceUpload()
    if ScriptMappingPipeline.upload.head > ScriptMappingPipeline.upload.tail then return nil end
    local item = ScriptMappingPipeline.upload.queue[ScriptMappingPipeline.upload.head]
    ScriptMappingPipeline.upload.queue[ScriptMappingPipeline.upload.head] = nil
    ScriptMappingPipeline.upload.head += 1
    if item then ScriptMappingPipeline.upload.bytes = math.max(0, ScriptMappingPipeline.upload.bytes - (item.queuedBytes or 0)) end
    return item
end

local function ResetScriptSourceUploadQueue()
    ScriptMappingPipeline.upload.queue = {}
    ScriptMappingPipeline.upload.head = 1
    ScriptMappingPipeline.upload.tail = 0
    ScriptMappingPipeline.upload.bytes = 0
end

local function StartUploadQueue()
    if ScriptMappingPipeline.upload.thread then return end

    ScriptMappingPipeline.upload.thread = task.spawn(function()
        while true do
            if not IsScriptMappingTransportReady(ScriptMappingPipeline.clientId) then
                task.wait(UploadFlushInterval)
                continue
            end
            if ScriptMappingPipeline.upload.head > ScriptMappingPipeline.upload.tail then
                if ScriptMappingPipeline.statusDirty then
                    local stateVersion = ScriptMappingPipeline.stateVersion
                    local uploaded = UploadScriptSourceBatch(
                        ScriptMappingPipeline.clientId,
                        {}
                    )
                    if uploaded and ScriptMappingPipeline.stateVersion == stateVersion then
                        ScriptMappingPipeline.statusDirty = false
                    end
                end
                task.wait(UploadFlushInterval)
                continue
            end

            local batch = {}
            local batchBytes = 0
            while ScriptMappingPipeline.upload.head <= ScriptMappingPipeline.upload.tail and #batch < UploadBatchMax do
                local nextItem = ScriptMappingPipeline.upload.queue[ScriptMappingPipeline.upload.head]
                local nextBytes = if nextItem and type(nextItem.source) == "string" then #nextItem.source else 0
                if #batch > 0 and batchBytes + nextBytes > UploadBatchMaxBytes then break end

                local item = DequeueScriptSourceUpload()
                if not item then continue end
                local job = ScriptMappingPipeline.jobs[item.debugId]
                local itemIsCurrent = item.generation == ScriptMappingPipeline.generation and job ~= nil
                local itemIsReady = itemIsCurrent and (
                    (item.kind == "source" and job.state == "awaiting_upload") or
                    (item.kind == "remove" and job.state == "removed")
                )
                if itemIsReady then
                    table.insert(batch, item)
                    batchBytes += nextBytes
                end
            end
            if #batch == 0 then continue end

            local stateVersion = ScriptMappingPipeline.stateVersion
            local uploaded = UploadScriptSourceBatch(ScriptMappingPipeline.clientId, batch)
            if uploaded then
                local changedCount = 0
                for _, item in batch do
                    if item.kind == "source" and item.generation == ScriptMappingPipeline.generation then
                        if JobStatus:MarkMapped(item.debugId, false) then
                            changedCount += 1
                        end
                    end
                end
                ScriptMappingPipeline.statusDirty =
                    ScriptMappingPipeline.stateVersion ~= stateVersion + changedCount
            else
                local mappingStateChanged = false
                for idx = #batch, 1, -1 do
                    local item = batch[idx]
                    if item.generation ~= ScriptMappingPipeline.generation then
                        continue
                    end

                    item.attempts = (item.attempts or 0) + 1
                    if item.kind == "source" and item.attempts >= UploadMaxAttempts then
                        mappingStateChanged = JobStatus:MarkFailed(
                            item.debugId,
                            "Source upload failed after " .. tostring(item.attempts) .. " attempts.",
                            false
                        ) or mappingStateChanged
                    else
                        EnqueueScriptSourceUpload(item)
                    end
                end
                if mappingStateChanged then JobStatus:Publish() end
                local attempts = batch[1] and batch[1].attempts or 1
                task.wait(math.min(2 ^ math.max(0, attempts - 1), UploadRetryMaxSeconds))
            end

            task.wait()
        end
    end)
end

return {
    EnqueueScriptSourceUpload = EnqueueScriptSourceUpload,
    IsScriptMappingTransportReady = IsScriptMappingTransportReady,
    ResetScriptSourceUploadQueue = ResetScriptSourceUploadQueue,
    StartUploadQueue = StartUploadQueue,
    UploadQueueMaxBytes = 32 * 1024 * 1024,
}
end
