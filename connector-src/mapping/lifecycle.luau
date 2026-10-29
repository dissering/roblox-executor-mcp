return function(dependencies)
local ScriptMappingPipeline = dependencies.ScriptMappingPipeline
local WorkerPool = dependencies.WorkerPool
local UploadSession = dependencies.UploadSession
local GenerateSessionGuid = dependencies.GenerateSessionGuid
local CoreGui = dependencies.CoreGui
local CorePackages = dependencies.CorePackages
local ScriptContext = dependencies.ScriptContext
local getnilinstances = dependencies.getnilinstances
local ScriptMappingWorkerCount = dependencies.WorkerCount
local Concurrency = dependencies.Concurrency
local JobStatus = dependencies.JobStatus
local FailedResync = dependencies.FailedResync
local UploadClient = dependencies.UploadClient
local DecompilerClient = dependencies.DecompilerClient
local EnqueueScriptSourceUpload = UploadClient.EnqueueScriptSourceUpload
local IsScriptMappingTransportReady = UploadClient.IsScriptMappingTransportReady
local ResetScriptSourceUploadQueue = UploadClient.ResetScriptSourceUploadQueue
local DecompileScriptSource = DecompilerClient.DecompileScriptSource
local FetchCachedScriptSources = DecompilerClient.FetchCachedScriptSources
local GetScriptHashForInstance = DecompilerClient.GetScriptHashForInstance
local PrepareScriptForMapping = DecompilerClient.PrepareScriptForMapping
local RefreshDecompilerPlan = DecompilerClient.RefreshDecompilerPlan
local ResetDecompilerClient = DecompilerClient.ResetDecompilerClient
local MappingMaxAttempts = 4
local MappingRetryMaxSeconds = 8
local SourceCacheLookupBatchMax = 256
local HandleMappingWorkerError

local function GetDataModelScripts()
    local ok, scripts = pcall(function() return game:QueryDescendants("LuaSourceContainer") end)
    if ok and type(scripts) == "table" then return scripts end
    local result = {}
    for _, instance in game:GetDescendants() do
        if instance:IsA("LuaSourceContainer") then table.insert(result, instance) end
    end
    return result
end

local function PublishCurrentMappingStatus()
    JobStatus:Publish()
end

local function RemoveScriptFromMapping(debugId, generation)
    local job = ScriptMappingPipeline.jobs[debugId]
    if generation ~= ScriptMappingPipeline.generation or not job or job.state == "removed" then return end

    ScriptMappingPipeline.instances[debugId] = nil
    ScriptMappingPipeline:SetJobState(job, "removed")
    job.script = nil
    job.prepared = nil
    EnqueueScriptSourceUpload({
        kind = "remove",
        debugId = debugId,
        generation = generation,
        attempts = 0,
    })
end

local function AttachScriptToMappingJob(job, script)
    job.script = script
    ScriptMappingPipeline.instances[job.debugId] = script
    if job.destroyingConnection then return end
    local generation = job.generation
    job.destroyingConnection = script.Destroying:Once(function()
        RemoveScriptFromMapping(job.debugId, generation)
    end)
end

local function TrackScriptForMapping(debugId)
    return ScriptMappingPipeline:TrackJob(debugId) ~= nil
end

local function DeferScriptMappingUntilTransport(script, prepared, generation, knownDebugId)
    local debugId = knownDebugId or script:GetDebugId()
    local job = ScriptMappingPipeline.jobs[debugId]
    if generation ~= ScriptMappingPipeline.generation or not job then return end
    if job.state == "mapped" or job.state == "failed" or job.state == "removed" then return end

    ScriptMappingPipeline:SetJobState(job, "deferred")
    AttachScriptToMappingJob(job, script)
    job.prepared = prepared
end

local function RetryScriptMapping(script, prepared, generation, errorMessage, knownDebugId)
    local debugId = knownDebugId or script:GetDebugId()
    local job = ScriptMappingPipeline.jobs[debugId]
    if generation ~= ScriptMappingPipeline.generation or not job then return end
    if job.state == "mapped" or job.state == "failed" or job.state == "removed" then return end
    if string.find(tostring(errorMessage), "Timed out", 1, true) then
        Concurrency:Reduce()
    end

    job.mappingAttempts = (job.mappingAttempts or 0) + 1
    if job.mappingAttempts >= MappingMaxAttempts then
        JobStatus:MarkFailed(debugId, errorMessage or "Failed to prepare or decompile script source.")
        return
    end

    ScriptMappingPipeline:SetJobState(job, "queued")
    AttachScriptToMappingJob(job, script)
    job.prepared = prepared
    local retryDelay = math.min(2 ^ math.max(0, job.mappingAttempts - 1), MappingRetryMaxSeconds)
    task.delay(retryDelay, function()
        if generation ~= ScriptMappingPipeline.generation or job.generation ~= generation then return end
        if job.state ~= "queued" then return end
        if not IsScriptMappingTransportReady(ScriptMappingPipeline.clientId) then
            DeferScriptMappingUntilTransport(script, prepared, generation, debugId)
            return
        end

        ScriptMappingPipeline.workers:QueueOperation(script, prepared, generation, debugId)
    end)
end

local function QueueMappedScriptSource(script, source, scriptHash, generation, knownDebugId)
    local debugId = knownDebugId or script:GetDebugId()
    local job = ScriptMappingPipeline.jobs[debugId]
    if not job then
        TrackScriptForMapping(debugId)
        job = ScriptMappingPipeline.jobs[debugId]
    elseif job.state == "failed" then
        TrackScriptForMapping(debugId)
    elseif job.state == "mapped" or job.state == "awaiting_upload" or job.state == "removed" then
        return false
    end

    local path = script:GetFullName()
    AttachScriptToMappingJob(job, script)

    ScriptMappingPipeline:SetJobState(job, "awaiting_upload")
    EnqueueScriptSourceUpload({
        kind = "source",
        debugId = debugId,
        path = path,
        source = source,
        scriptHash = scriptHash,
        attempts = 0,
        generation = generation,
    })
    return true
end

local function MapScriptSource(script, prepared, generation, knownDebugId)
    if generation ~= ScriptMappingPipeline.generation then return end

    local debugId = knownDebugId or script:GetDebugId()
    local job = ScriptMappingPipeline.jobs[debugId]
    if not job or job.state ~= "queued" then return end
    if not IsScriptMappingTransportReady(ScriptMappingPipeline.clientId) then
        DeferScriptMappingUntilTransport(script, prepared, generation, debugId)
        return
    end
    if not ScriptMappingPipeline:TryStartMapping(job) then return end

    while ScriptMappingPipeline.upload.bytes >= UploadClient.UploadQueueMaxBytes do
        if generation ~= ScriptMappingPipeline.generation then return end
        if not IsScriptMappingTransportReady(ScriptMappingPipeline.clientId) then
            DeferScriptMappingUntilTransport(script, prepared, generation, debugId)
            return
        end
        task.wait(0.05)
    end

    AttachScriptToMappingJob(job, script)
    local clientId = ScriptMappingPipeline.clientId
    if not prepared then
        local prepareError
        prepared, prepareError = PrepareScriptForMapping(
            script,
            true,
            generation,
            clientId,
            job.initialProviderId
        )
        if not prepared then
            RetryScriptMapping(script, nil, generation, prepareError, debugId)
            return
        end
    end
    job.prepared = prepared
    local source, errorMessage, scriptHash, usedPrepared = DecompileScriptSource(
        script,
        prepared,
        generation,
        clientId
    )
    job.prepared = usedPrepared
    if not job.initialProviderId and usedPrepared then
        job.initialProviderId = usedPrepared.initialProviderId
    end
    if not source then
        RetryScriptMapping(script, usedPrepared, generation, errorMessage, debugId)
        return
    end
    if generation ~= ScriptMappingPipeline.generation then return end
    if ScriptMappingPipeline.jobs[debugId] ~= job then return end
    if job.state == "mapped" or job.state == "failed" or job.state == "removed" then return end
    job.mappingAttempts = 0
    Concurrency:RecordSuccess()

    QueueMappedScriptSource(script, source, scriptHash, generation, debugId)
end

HandleMappingWorkerError = function(errorMessage, script, prepared, generation, debugId)
    if generation ~= ScriptMappingPipeline.generation or type(debugId) ~= "string" then return end
    RetryScriptMapping(script, prepared, generation, tostring(errorMessage), debugId)
end

ScriptMappingPipeline.workers = WorkerPool.new({
    MaxConcurrent = ScriptMappingWorkerCount,
    MainCallback = MapScriptSource,
    OnError = HandleMappingWorkerError,
})

local function GetScriptByDebugId(debugId)
    local CachedInstance = ScriptMappingPipeline.instances[debugId]
    if CachedInstance then
        return CachedInstance
    end

    for _, script in GetDataModelScripts() do
        if script:IsA("Script") and script.RunContext == Enum.RunContext.Server then continue end
        if script:GetDebugId() ~= debugId then continue end
        
        ScriptMappingPipeline.instances[debugId] = script
        return script
    end

    for _, script in getnilinstances() do
        if not script:IsA("LuaSourceContainer") then continue end

        if script:IsA("Script") and script.RunContext ~= Enum.RunContext.Client then continue end
        if script:GetDebugId() ~= debugId then continue end
        
        ScriptMappingPipeline.instances[debugId] = script
        return script
    end

    return nil
end

local function RetryFailedScripts()
    if not IsScriptMappingTransportReady(ScriptMappingPipeline.clientId) then return end

    FailedResync:ProcessDue(function(job)
        local script = GetScriptByDebugId(job.debugId)
        if not script then
            FailedResync:Defer(job)
            return
        end
        if not FailedResync:Claim(job) then return end

        AttachScriptToMappingJob(job, script)
        ScriptMappingPipeline.workers:QueueOperation(
            script,
            nil,
            job.generation,
            job.debugId
        )
    end, function(job, handleError)
            if job.state == "failed" then
                FailedResync:Defer(job)
            else
                JobStatus:MarkFailed(
                    job.debugId,
                    "Failed to run periodic resync: " .. tostring(handleError)
                )
            end
    end)
end

local function StartFailedScriptResync()
    FailedResync:Start(RetryFailedScripts)
end

local function IsCandidateScriptForMapping(script)
    local IsServerScript = (
        script:IsA("Script") and (
            script.RunContext == Enum.RunContext.Server or
            script.RunContext == Enum.RunContext.Legacy
        )
    )
    if IsServerScript then return false end

    local IsRobloxScript = (
        script.RobloxLocked or
        (CoreGui and script:IsDescendantOf(CoreGui)) or
        (CorePackages and script:IsDescendantOf(CorePackages)) or
        (ScriptContext and script:IsDescendantOf(ScriptContext))
    )
    if IsRobloxScript then return false end

    local debugId = script:GetDebugId()
    if ScriptMappingPipeline.jobs[debugId] then return false end

    return true
end

local function QueueScriptForMapping(script, prepared)
    local debugId = script:GetDebugId()
    if not TrackScriptForMapping(debugId) then return end
    AttachScriptToMappingJob(ScriptMappingPipeline.jobs[debugId], script)

    JobStatus:Publish()
    local generation = ScriptMappingPipeline.generation
    if IsScriptMappingTransportReady(ScriptMappingPipeline.clientId) then
        ScriptMappingPipeline.workers:QueueOperation(script, prepared, generation, debugId)
    else
        DeferScriptMappingUntilTransport(script, prepared, generation, debugId)
    end
end

local function ResumeDeferredScriptMappings()
    if not IsScriptMappingTransportReady(ScriptMappingPipeline.clientId) then return end

    for debugId, job in ScriptMappingPipeline.jobs do
        if job.generation == ScriptMappingPipeline.generation and job.state == "deferred" then
            ScriptMappingPipeline:SetJobState(job, "queued")
            ScriptMappingPipeline.workers:QueueOperation(job.script, job.prepared, job.generation, debugId)
        end
    end
end

local function StartScriptMapping(clientId)
    if not IsScriptMappingTransportReady(clientId) then return end

    ScriptMappingPipeline.clientId = clientId
    RefreshDecompilerPlan(true, ScriptMappingPipeline.generation, clientId)

    if not ScriptMappingPipeline.descendantConnection then
        ScriptMappingPipeline.descendantConnection = game.DescendantAdded:Connect(function(script)
            if not script:IsA("LuaSourceContainer") then
                return
            end

            if not IsCandidateScriptForMapping(script) then return end
            QueueScriptForMapping(script)
        end)
    end

    if ScriptMappingPipeline.initialScanRunning or ScriptMappingPipeline.initialScanFinished then return end
    ScriptMappingPipeline.initialScanRunning = true
    local generation = ScriptMappingPipeline.generation

    --// Map script sources \\--
    task.spawn(function()
        local ScriptsToQueue = {}
        local scanCompleted = false
        local success, scanError = pcall(function()
            local CategoriesToMap = {
                GetDataModelScripts(),
                getnilinstances()
            }
            local seenDebugIds = {}

            for _, category in CategoriesToMap do
                for _, script in category do
                    if generation ~= ScriptMappingPipeline.generation then return end
                    local candidateOk, debugId = pcall(function()
                        if not script:IsA("LuaSourceContainer") then return nil end
                        if not IsCandidateScriptForMapping(script) then return nil end
                        return script:GetDebugId()
                    end)
                    if not candidateOk then
                        continue
                    end
                    if not debugId then continue end
                    if seenDebugIds[debugId] then continue end
                    seenDebugIds[debugId] = true
                    if not TrackScriptForMapping(debugId) then continue end
                    AttachScriptToMappingJob(ScriptMappingPipeline.jobs[debugId], script)
                    table.insert(ScriptsToQueue, { script = script, debugId = debugId })
                end
            end

            JobStatus:Publish()

            local hashesToFetch = {}
            local scriptsToDispatch = {}
            local function flushPreparedScripts()
                FetchCachedScriptSources(clientId, hashesToFetch)
                for _, item in scriptsToDispatch do
                    if generation ~= ScriptMappingPipeline.generation then return end
                    if IsScriptMappingTransportReady(clientId) then
                        ScriptMappingPipeline.workers:QueueOperation(item.script, nil, generation, item.debugId)
                    else
                        DeferScriptMappingUntilTransport(item.script, nil, generation, item.debugId)
                    end
                end
                table.clear(hashesToFetch)
                table.clear(scriptsToDispatch)
            end

            for idx, item in ScriptsToQueue do
                if generation ~= ScriptMappingPipeline.generation then return end
                local scriptHash = GetScriptHashForInstance(item.script)
                if scriptHash then table.insert(hashesToFetch, scriptHash) end
                table.insert(scriptsToDispatch, item)

                if #scriptsToDispatch >= SourceCacheLookupBatchMax then
                    flushPreparedScripts()
                end
                if idx % 250 == 0 then task.wait() end
            end
            flushPreparedScripts()

            scanCompleted = true
        end)

        if generation ~= ScriptMappingPipeline.generation then return end
        ScriptMappingPipeline.initialScanRunning = false
        if success and scanCompleted then
            ScriptMappingPipeline.initialScanFinished = true
            ScriptMappingPipeline.stateVersion += 1
            PublishCurrentMappingStatus()
            return
        end

        for _, item in ScriptsToQueue do
            local job = ScriptMappingPipeline.jobs[item.debugId]
            if ScriptMappingPipeline:CanDeferScanJob(job, generation) then
                local deferredOk, deferredError = pcall(
                    DeferScriptMappingUntilTransport,
                    item.script,
                    job.prepared,
                    generation,
                    item.debugId
                )
                if not deferredOk then
                    local retryOk, retryError = pcall(
                        RetryScriptMapping,
                        item.script,
                        job.prepared,
                        generation,
                        tostring(deferredError),
                        item.debugId
                    )
                    if not retryOk then
                        JobStatus:MarkFailed(
                            item.debugId,
                            "Scan recovery failed: " .. tostring(retryError),
                            false
                        )
                    end
                end
            end
        end
        task.delay(1, function()
            ResumeDeferredScriptMappings()
            StartScriptMapping(clientId)
        end)
    end)
end

local function ResetScriptMappingState(clientId)
    local previousDescendantConnection = ScriptMappingPipeline.descendantConnection
    local nextGeneration = ScriptMappingPipeline.generation + 1
    local session = UploadSession.new(
        GenerateSessionGuid(),
        DateTime.now().UnixTimestampMillis,
        nextGeneration
    )
    ScriptMappingPipeline:Reset(clientId, session)
    ResetDecompilerClient()

    if previousDescendantConnection then
        previousDescendantConnection:Disconnect()
        ScriptMappingPipeline.descendantConnection = nil
    end

    if ScriptMappingPipeline.workers then
        ScriptMappingPipeline.workers:SetMaxConcurrent(ScriptMappingPipeline.currentWorkers)
        ScriptMappingPipeline.workers:Reset()
    end

    ResetScriptSourceUploadQueue()
end

return {
    DecompileScriptSource = DecompileScriptSource,
    GetScriptByDebugId = GetScriptByDebugId,
    QueueMappedScriptSource = QueueMappedScriptSource,
    ResetScriptMappingState = ResetScriptMappingState,
    ResumeDeferredScriptMappings = ResumeDeferredScriptMappings,
    StartFailedScriptResync = StartFailedScriptResync,
    StartScriptMapping = StartScriptMapping,
}
end
