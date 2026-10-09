local a={cache={}::any}do do local function __modImpl()return function(b)
local c=b.HttpService
local d=b.BridgeURL
local e=b.WebSocketAvailable
local f=b.GetRegistrationInfo
local g=b.SanitizeForOutput
local h=b.LuaEncode


local i={};do
i.__index=i

function i.BindToType(j,k,l)
j.Callbacks[k]=l
end

function i.BindToTypeRaw(j,k,l)
j.Callbacks[k]=l
j.RawCallbacks=j.RawCallbacks or{}
j.RawCallbacks[k]=true
end

function i.CreateAlias(j,k,l)
for m,n in l do
j.Callbacks[n]=j.Callbacks[k]
if j.RawCallbacks and j.RawCallbacks[k]then
j.RawCallbacks[n]=true
end
end
end

function i.Destroy(j)
j.Connected=false
for k,l in{"AliveThread","PollThread","ProbeThread"}do
local m=j[l]
j[l]=nil
if m then pcall(task.cancel,m)end
end
for k,l in{"MessageConnection","CloseConnection"}do
local m=j[l]
j[l]=nil
if m then m:Disconnect()end
end
if j.WebSocket then
pcall(function()j.WebSocket:Close()end)
j.WebSocket=nil
end
table.clear(j.Callbacks)
if j.RawCallbacks then table.clear(j.RawCallbacks)end
end

function i.HandleMessage(j,k)
if j.Callbacks[k.type]then
local l,m=pcall(function()
return j.Callbacks[k.type](k)
end)

if l and m==nil then
return nil
end

if not l then
return j:FormatResponse(m,k.id,true)
end

if j.RawCallbacks and j.RawCallbacks[k.type]then
return{
output=tostring(m),
success=true,
id=k.id
}
end

return j:FormatResponse(m,k.id,false)
end
return nil
end

function i.FormatResponse(j,k,l,m)
if m then
return{
error=tostring(k),
success=false,
id=l
}
end

local n=g(k)
if typeof(n)~="table"then
n={n}
end

return{
output=h(n,{
Prettify=false
}),
success=true,
id=l
}
end

function i.IsAlive(j)
local k,l=pcall(function()
local k
local l=task.spawn(function()
local l,m=pcall(request,{
Url="http://"..d,
Method="GET"
})

if l then
k=m
end
end)
j.ProbeThread=l

local m=os.clock()
repeat task.wait(0.05)until k~=nil or os.clock()-m>5
j.ProbeThread=nil

if k==nil then
task.cancel(l)
return false
end


if k.StatusCode==426 or k.StatusCode==200 then
return true
end

return false
end)

if not k then
return false
end

return l
end
end


local j=setmetatable({},{__index=i});do
j.__index=j

function j.new()
local k=setmetatable({},j)


local l=0.5
local m=5
local n=10
local o=0

while not k:IsAlive()do
o+=1
if o>=n then
error("Failed to connect to bridge server after "..n.." attempts")
end
task.wait(l)
l=math.min(l*1.5,m)
end


local p
local q=task.spawn(function()
local q,r=pcall(function()
return WebSocket.connect("ws://"..d)
end)
if q then
p=r
end
end)

local r=os.clock()
repeat task.wait(0.05)until p~=nil or os.clock()-r>5

if p==nil then
task.cancel(q)
error"WebSocket connection timed out after 5 seconds"
end

k.WebSocket=p
k.Connected=true
k.Callbacks={}
k.ClientId=nil

k.AliveThread=task.spawn(function()
local s=0
while k.Connected do
task.wait(1)
if not k.Connected then
break
end

if k:IsAlive()then
s=0
continue
end

s+=1
if s<3 then
continue
end

k.Connected=false
break
end

pcall(function()
k.WebSocket:Close()
end)
end)


k.MessageConnection=k.WebSocket.OnMessage:Connect(function(s)
local t=c:JSONDecode(s)


if t.type=="registered"then
k.ClientId=t.clientId
return
end

local u=k:HandleMessage(t)
if u then
k.WebSocket:Send(c:JSONEncode(u))
end
end)


k.CloseConnection=k.WebSocket.OnClose:Connect(function()
k.Connected=false
end)

local s,t=pcall(function()
k.WebSocket:Send(c:JSONEncode(f()))
end)
if not s then
k:Destroy()
error(t)
end

return k
end

function j.WaitForDisconnect(k)
while k.Connected do
task.wait(0.1)
end
end
end


local k=setmetatable({},{__index=i});do
k.__index=k

function k.new()
local l=setmetatable({},k)


local m=0.5
local n=5
local o=10
local p=0

while not l:IsAlive()do
p+=1
if p>=o then
error("Failed to connect to bridge server after "..o.." attempts")
end
task.wait(m)
m=math.min(m*1.5,n)
end

l.Connected=true
l.Callbacks={}
l.PollInterval=0.1
l.ClientId=nil


pcall(function()
local q=request{
Url="http://"..d.."/register",
Method="POST",
Headers={["Content-Type"]="application/json"},
Body=c:JSONEncode(f()),
}
if q.StatusCode==200 and q.Body then
local r=c:JSONDecode(q.Body)
l.ClientId=r.clientId
end
end)


l.PollThread=task.spawn(function()
local q=0

while l.Connected do
local r=false local
s=pcall(function()
local s="http://"..d.."/poll"
if l.ClientId then
s=s.."?clientId="..l.ClientId
end
local t=request{
Url=s,
Method="GET"
}


if t.StatusCode~=204 and t.StatusCode~=200 then
q+=1
if q>=3 then
l.Connected=false
end

return
end

q=0


if t.Body and t.Body~=""then
local u=c:JSONDecode(t.Body)
local v={}
if typeof(u)=="table"and u.type==nil and#u>0 then
v=u
elseif typeof(u)=="table"and u.type~=nil then
v={u}
end

for w,x in ipairs(v)do
r=true
task.spawn(function()
local y=l:HandleMessage(x)
if y==nil then return end


request{
Url="http://"..d.."/respond",
Method="POST",
Headers={
["Content-Type"]="application/json"
},
Body=c:JSONEncode(y)
}
end)
end
end
end)

if not s then
q+=1
if q>=3 then
l.Connected=false
end
end

if not r then
task.wait(l.PollInterval)
end
end
end)

return l
end

function k.WaitForDisconnect(l)
while l.Connected do
task.wait(0.1)
end
end
end


local function CreateBridge()
if e then
local l,m=pcall(function()
return j.new()
end)

if l then
return m
end
end

return k.new()
end

return{
CreateBridge=CreateBridge,
}
end end function a.a():typeof(__modImpl())local b=a.cache.a if not b then b={c=__modImpl()}a.cache.a=b end return b.c end end do local function __modImpl()

local b={}
b.__index=b

function b.new(c)
local d=setmetatable(c,b)
d.Queue={}
d.QueueHead=1
d.QueueTail=0
d.ActiveWorkers=0
d.ManagerGeneration=0
d.IsDestroyed=false
d.TaskLibrary=c.TaskLibrary or task
d:Reset()
return d
end

function b.QueueOperation(c,...)
if c.IsDestroyed then return end
c.QueueTail+=1
c.Queue[c.QueueTail]=table.pack(...)
c:DrainQueue()
end

function b.DrainQueue(c,d)
if c.IsDestroyed then return end
if d~=nil and c.ManagerGeneration~=d then return end

local e=c.ManagerGeneration
while c.ActiveWorkers<c.MaxConcurrent and c.QueueHead<=c.QueueTail do
local f=c.Queue[c.QueueHead]
c.Queue[c.QueueHead]=nil
c.QueueHead+=1
if not f then continue end

c.ActiveWorkers+=1
c.TaskLibrary.defer(function()
local g=f
while g do
if not c.IsDestroyed and c.ManagerGeneration==e then
local h,i=pcall(
c.MainCallback,
table.unpack(g,1,g.n)
)
if not h then
if c.OnError then
pcall(
c.OnError,
i,
table.unpack(g,1,g.n)
)
end
end
end

if c.IsDestroyed or c.ManagerGeneration~=e or c.ActiveWorkers>c.MaxConcurrent then
break
end

if c.QueueHead<=c.QueueTail then
g=c.Queue[c.QueueHead]
c.Queue[c.QueueHead]=nil
c.QueueHead+=1
else
g=nil
end
end



c.ActiveWorkers=math.max(0,c.ActiveWorkers-1)
c:DrainQueue()
end)
end
end

function b.Reset(c)
if c.IsDestroyed then return end
c.Queue={}
c.QueueHead=1
c.QueueTail=0
c.ManagerGeneration+=1
c:DrainQueue()
end

function b.SetMaxConcurrent(c,d)
c.MaxConcurrent=math.max(1,math.floor(tonumber(d)or 1))
c:DrainQueue()
end

function b.Destroy(c)
if c.IsDestroyed then return end
c.IsDestroyed=true
table.clear(c.Queue)
c.QueueHead=1
c.QueueTail=0
end

b.Stop=b.Destroy

return b end function a.b():typeof(__modImpl())local b=a.cache.b if not b then b={c=__modImpl()}a.cache.b=b end return b.c end end do local function __modImpl()

local b={}
b.__index=b

local c={
mapped=true,
failed=true,
}

local d={
queued={mapping=true,deferred=true,awaiting_upload=true,failed=true,removed=true},
mapping={queued=true,deferred=true,awaiting_upload=true,failed=true,removed=true},
deferred={queued=true,awaiting_upload=true,failed=true,removed=true},
awaiting_upload={mapped=true,failed=true,removed=true},
mapped={removed=true},
failed={queued=true,removed=true},
removed={},
}

function b.new()
return setmetatable({
jobs={},
instances=setmetatable({},{__mode="v"}),
total=0,
processed=0,
skipped=0,
disabled=false,
statusDirty=false,
clientId=nil,
workers=nil,
configuredWorkers=0,
currentWorkers=0,
successesSinceWorkerAdjustment=0,
descendantConnection=nil,
initialScanRunning=false,
initialScanFinished=false,
generation=0,
session=nil,
stateVersion=0,
upload={
queue={},
head=1,
tail=0,
bytes=0,
thread=nil,
},
bridge=nil,
sourceCacheByHash={},
sourceCacheCheckedByHash={},
scriptHashByDebugId={},
},b)
end

function b.IsActiveSession(e,f,g,h)
return(
e.session==f and
e.generation==g and
e.clientId==h
)
end

function b.IsFinished(e,f)
local g=f==nil and e.processed or f
return e.disabled or(
e.initialScanFinished and
g>=e.total
)
end

function b.Reset(e,f,g)
e.generation+=1
e.session=g
e.stateVersion=0
e.currentWorkers=e.configuredWorkers
e.successesSinceWorkerAdjustment=0
e.jobs={}
e.instances=setmetatable({},{__mode="v"})
e.total=0
e.processed=0
e.skipped=0
e.statusDirty=true
e.disabled=false
e.clientId=f
e.scriptHashByDebugId={}
e.sourceCacheCheckedByHash={}
e.initialScanRunning=false
e.initialScanFinished=false
end

function b.EnsureJob(e,f)
local g=e.jobs[f]
if g then return g,false end

g={debugId=f,generation=e.generation}
e.jobs[f]=g
e.total+=1
e.stateVersion+=1
e.statusDirty=true
return g,true
end

function b.TrackJob(e,f)
local g=e.jobs[f]
if g and g.state~="failed"then return nil end

if not g then
g=e:EnsureJob(f)
else
g.generation=e.generation
end
g.mappingAttempts=0
e:SetJobState(g,"queued")
return g
end

function b.TryStartMapping(e,f)
if e.jobs[f.debugId]~=f or f.generation~=e.generation then return false end
if f.state~="queued"then return false end
e:SetJobState(f,"mapping")
return true
end

function b.CanDeferScanJob(e,f,g)
return(
f~=nil and
f.generation==g and
g==e.generation and
f.state=="queued"
)
end

function b.SetJobState(e,f,g)
local h=f.state
if h==g then return false end
if h~=nil and not d[h][g]then
error("Invalid script mapping transition: "..tostring(h).." -> "..tostring(g))
end

if h=="mapped"then
e.processed=math.max(0,e.processed-1)
elseif h=="failed"then
e.processed=math.max(0,e.processed-1)
e.skipped=math.max(0,e.skipped-1)
end

if g=="mapped"then
e.processed+=1
elseif g=="failed"then
e.processed+=1
e.skipped+=1
elseif g=="removed"then
e.total=math.max(0,e.total-1)
end

f.state=g
if c[h]or c[g]or g=="removed"then
e.stateVersion+=1
e.statusDirty=true
end
return true
end

return b end function a.c():typeof(__modImpl())local b=a.cache.c if not b then b={c=__modImpl()}a.cache.c=b end return b.c end end do local function __modImpl()

local b={}
b.__index=b
local c=0

function b.new(d,e,f)
local g=math.max(0,math.floor(tonumber(e)or 0))
local h=math.max(g,c+1)
c=h
return setmetatable({
id=d,
startedAt=h,
generation=f,
revision=0,
started=false,
},b)
end

function b.NextRevision(d)
d.revision+=1
return d.revision
end

function b.MarkStarted(d)
d.started=true
end

return b end function a.d():typeof(__modImpl())local b=a.cache.d if not b then b={c=__modImpl()}a.cache.d=b end return b.c end end do local function __modImpl()

local b={}

function b.CanAttemptBuiltIn(c,d,e)
return(
c.builtinAttempted~=true and
c.builtinDisabled~=true and
d<=e
)
end

function b.MarkBuiltInAttempted(c)
c.builtinAttempted=true
end

function b.DisableBuiltIn(c)
c.builtinAttempted=true
c.builtinDisabled=true
c.useDirectBuiltin=false
end

return b end function a.e():typeof(__modImpl())local b=a.cache.e if not b then b={c=__modImpl()}a.cache.e=b end return b.c end end do local function __modImpl()

local b=a.e()

local c={}

function c.MaterializeServerFallback(d,e)
b.DisableBuiltIn(d)
if type(d.bytecode)=="string"then
return true
end

local f,g=e()
if not f then
return false,g
end

d.bytecode=g
return true
end

return c end function a.f():typeof(__modImpl())local b=a.cache.f if not b then b={c=__modImpl()}a.cache.f=b end return b.c end end do local function __modImpl()

local b={}
b.__index=b

function b.new(c,d)
c.configuredWorkers=d
c.currentWorkers=d
return setmetatable({pipeline=c},b)
end

function b.Reduce(c)
local d=c.pipeline
local e=math.max(4,math.floor(d.currentWorkers/2))
if e>=d.currentWorkers then return end

d.currentWorkers=e
d.successesSinceWorkerAdjustment=0
if d.workers then
d.workers:SetMaxConcurrent(e)
end
end

function b.RecordSuccess(c)
local d=c.pipeline
if d.currentWorkers>=d.configuredWorkers then return end

d.successesSinceWorkerAdjustment+=1
if d.successesSinceWorkerAdjustment<100 then return end

d.successesSinceWorkerAdjustment=0
d.currentWorkers+=1
if d.workers then
d.workers:SetMaxConcurrent(d.currentWorkers)
end
end

return b end function a.g():typeof(__modImpl())local b=a.cache.g if not b then b={c=__modImpl()}a.cache.g=b end return b.c end end do local function __modImpl()

local b={}
b.__index=b

function b.new(c,d)
d=d or{}
return setmetatable({
pipeline=c,
clock=d.Clock or os.clock,
taskLibrary=d.TaskLibrary or task,
intervalSeconds=d.IntervalSeconds or 30,
maxDelaySeconds=d.MaxDelaySeconds or 300,
batchSize=d.BatchSize or 8,
thread=nil,
},b)
end

function b.Schedule(c,d)
local e=math.max(0,d.resyncRounds or 0)
local f=math.min(
c.intervalSeconds*(2^e),
c.maxDelaySeconds
)
d.nextResyncAt=c.clock()+f
end

function b.Cancel(c,d)
d.nextResyncAt=nil
d.resyncRounds=nil
end

function b.Defer(c,d)
d.nextResyncAt=c.clock()+c.intervalSeconds
end

function b.GetDue(c,d)
d=d or c.clock()
local e={}
for f,g in c.pipeline.jobs do
if(
g.generation==c.pipeline.generation and
g.state=="failed"and
type(g.nextResyncAt)=="number"and
g.nextResyncAt<=d
)then
table.insert(e,g)
end
end

table.sort(e,function(f,g)
if f.nextResyncAt==g.nextResyncAt then
return f.debugId<g.debugId
end
return f.nextResyncAt<g.nextResyncAt
end)
while#e>c.batchSize do
table.remove(e)
end
return e
end

function b.Claim(c,d,e)
e=e or c.clock()
if c.pipeline.jobs[d.debugId]~=d then return false end
if d.generation~=c.pipeline.generation or d.state~="failed"then return false end
if type(d.nextResyncAt)~="number"or d.nextResyncAt>e then return false end

d.resyncRounds=(d.resyncRounds or 0)+1
d.nextResyncAt=nil
d.errorMessage=nil
return c.pipeline:TrackJob(d.debugId)==d
end

function b.Start(c,d)
if c.thread then return end
c.thread=c.taskLibrary.spawn(function()
while true do
c.taskLibrary.wait(c.intervalSeconds)
pcall(d)
end
end)
end

function b.ProcessDue(c,d,e)
for f,g in c:GetDue()do
local h,i=pcall(d,g)
if not h then
if e then
e(g,i)
else
c:Defer(g)
end
end
end
end

return b end function a.h():typeof(__modImpl())local b=a.cache.h if not b then b={c=__modImpl()}a.cache.h=b end return b.c end end do local function __modImpl()

local b={}
b.__index=b
local c=warn or print

function b.new(d,e)
return setmetatable({
pipeline=d,
failedResync=e,
},b)
end

function b.Publish(d)
d.pipeline.statusDirty=true
end

function b.MarkMapped(d,e,f)
local g=d.pipeline
local h=g.jobs[e]
if h and(h.state=="mapped"or h.state=="failed"or h.state=="removed")then
return false
end

if not h then
h=g:EnsureJob(e)
end

g:SetJobState(h,"mapped")
if d.failedResync then d.failedResync:Cancel(h)end
h.prepared=nil
h.script=nil
if f~=false then d:Publish()end
return true
end

function b.MarkFailed(d,e,f,g)
local h=d.pipeline
local i=h.jobs[e]
if i and(i.state=="mapped"or i.state=="failed"or i.state=="removed")then
return false
end

if not i then
i=h:EnsureJob(e)
end

h:SetJobState(i,"failed")
if d.failedResync then d.failedResync:Schedule(i)end
i.errorMessage=tostring(f or"unknown error")
i.prepared=nil
i.script=nil
c("[Roblox Executor MCP] Script mapping skipped "..tostring(e)..": "..tostring(f or"unknown error"))
if g~=false then d:Publish()end
return true
end

return b end function a.i():typeof(__modImpl())local b=a.cache.i if not b then b={c=__modImpl()}a.cache.i=b end return b.c end end do local function __modImpl()

return function(b)
local c=b.ScriptMappingPipeline
local d=b.HttpService
local e=b.BridgeURL
local f=b.JobStatus
local g=64
local h=8388608
local i=0.5
local j=5
local k=8

local function IsScriptMappingTransportReady(l)
return(
c.bridge~=nil and
c.bridge.Connected==true and
c.bridge.ClientId~=nil and
c.bridge.ClientId==l
)
end

local function UploadScriptSourceBatch(l,m)
if not l then return false end
if not IsScriptMappingTransportReady(l)then return false end
local n=c.generation
local o=c.session
if not o then return false end

local p={}
local q={}
for r,s in m or{}do
if s.kind=="remove"then
table.insert(q,s.debugId)
else
table.insert(p,{
debugId=s.debugId,
path=s.path,
source=s.source,
scriptHash=s.scriptHash,
})
end
end

local r=#p
local s=math.min(c.total,c.processed+r)
local t=c:IsFinished(s)
local u=o:NextRevision()

local v,w=pcall(request,{
Url="http://"..e.."/script-sources",
Method="POST",
Headers={
["Content-Type"]="application/json"
},
Body=d:JSONEncode{
clientId=l,
scripts=p,
removedScriptIds=q,
hasFinishedMapping=t,
sourcesToMap=c.total,
processedSources=s,
skippedSources=c.skipped,
mappingSessionId=o.id,
mappingSessionStartedAt=o.startedAt,
mappingRevision=u,
beginMappingSession=not o.started,
}
})

if not v or not w or w.StatusCode~=200 then return false,u end

if(
not c:IsActiveSession(o,n,l)
)then
return false,u,"stale_session"
end

local x=u
if type(w.Body)=="string"and w.Body~=""then
local y,z=pcall(function()
return d:JSONDecode(w.Body)
end)
if y and type(z)=="table"and type(z.acceptedMappingRevision)=="number"then
x=z.acceptedMappingRevision
end
end
if x~=u then return false,u end

o:MarkStarted()
return true,u
end

local function EnqueueScriptSourceUpload(l)
l.queuedBytes=if type(l.source)=="string"then#l.source else 0
c.upload.tail+=1
c.upload.queue[c.upload.tail]=l
c.upload.bytes+=l.queuedBytes
end

local function DequeueScriptSourceUpload()
if c.upload.head>c.upload.tail then return nil end
local l=c.upload.queue[c.upload.head]
c.upload.queue[c.upload.head]=nil
c.upload.head+=1
if l then c.upload.bytes=math.max(0,c.upload.bytes-(l.queuedBytes or 0))end
return l
end

local function ResetScriptSourceUploadQueue()
c.upload.queue={}
c.upload.head=1
c.upload.tail=0
c.upload.bytes=0
end

local function StartUploadQueue()
if c.upload.thread then return end

c.upload.thread=task.spawn(function()
while true do
if not IsScriptMappingTransportReady(c.clientId)then
task.wait(i)
continue
end
if c.upload.head>c.upload.tail then
if c.statusDirty then
local l=c.stateVersion
local m=UploadScriptSourceBatch(
c.clientId,
{}
)
if m and c.stateVersion==l then
c.statusDirty=false
end
end
task.wait(i)
continue
end

local l={}
local m=0
while c.upload.head<=c.upload.tail and#l<g do
local n=c.upload.queue[c.upload.head]
local o=if n and type(n.source)=="string"then#n.source else 0
if#l>0 and m+o>h then break end

local p=DequeueScriptSourceUpload()
if not p then continue end
local q=c.jobs[p.debugId]
local r=p.generation==c.generation and q~=nil
local s=r and(
(p.kind=="source"and q.state=="awaiting_upload")or
(p.kind=="remove"and q.state=="removed")
)
if s then
table.insert(l,p)
m+=o
end
end
if#l==0 then continue end

local n=c.stateVersion
local o=UploadScriptSourceBatch(c.clientId,l)
if o then
local p=0
for q,r in l do
if r.kind=="source"and r.generation==c.generation then
if f:MarkMapped(r.debugId,false)then
p+=1
end
end
end
c.statusDirty=
c.stateVersion~=n+p
else
local p=false
for q=#l,1,-1 do
local r=l[q]
if r.generation~=c.generation then
continue
end

r.attempts=(r.attempts or 0)+1
if r.kind=="source"and r.attempts>=j then
p=f:MarkFailed(
r.debugId,
"Source upload failed after "..tostring(r.attempts).." attempts.",
false
)or p
else
EnqueueScriptSourceUpload(r)
end
end
if p then f:Publish()end
local q=l[1]and l[1].attempts or 1
task.wait(math.min(2^math.max(0,q-1),k))
end

task.wait()
end
end)
end

return{
EnqueueScriptSourceUpload=EnqueueScriptSourceUpload,
IsScriptMappingTransportReady=IsScriptMappingTransportReady,
ResetScriptSourceUploadQueue=ResetScriptSourceUploadQueue,
StartUploadQueue=StartUploadQueue,
UploadQueueMaxBytes=33554432,
}
end end function a.j():typeof(__modImpl())local b=a.cache.j if not b then b={c=__modImpl()}a.cache.j=b end return b.c end end do local function __modImpl()

return function(b)
local c=b.ScriptMappingPipeline
local d=b.HttpService
local e=b.BridgeURL
local f=b.StripDecompilerBanner
local g=b.base64_encode
local h=b.BuiltInDecompile
local i=b.GetScriptHash
local j=b.DecompilerAttemptState
local k=b.PreparedScript
local l=b.Concurrency
local m=256
local n=2
local o=3
local p=8
local q=65
local r={
providerId=nil,
expiresAt=0,
refreshToken=nil,
blockedBuiltinUntil=0,
}
local s={
startedAt=nil,
lastAt=nil,
samples=0,
lastReportAt=0,
revision=0,
}

local function RunWithTimeout(t,u)
local v=false
local w=false
local x

local y=task.spawn(function()
w,x=pcall(u)
v=true
end)

local z=os.clock()+t
while not v and os.clock()<z do
task.wait(0.05)
end

if not v then
pcall(task.cancel,y)
return false,"Timed out after "..tostring(t).."s."
end

if not w then
return false,x
end

return true,x
end

local function RememberScriptSourceForHash(t,u)
if type(t)~="string"or t==""then return false end
if type(u)~="string"or u==""then return false end

c.sourceCacheByHash[t]=u
c.sourceCacheCheckedByHash[t]=true
return true
end

local function ReadScriptHash(t)
if type(i)~="function"then return nil end

local u,v=RunWithTimeout(n,function()
return i(t)
end)

if not u or type(v)~="string"or v==""then
return nil
end

return v
end

local function GetScriptHashForInstance(t)
local u=t:GetDebugId()
if c.scriptHashByDebugId[u]~=nil then
return c.scriptHashByDebugId[u]or nil
end

local v=ReadScriptHash(t)
c.scriptHashByDebugId[u]=v or false
return v
end

local function FetchCachedScriptSourceBatch(t,u)
if#u==0 then return true end

local v,w=pcall(request,{
Url="http://"..e.."/script-source-cache",
Method="POST",
Headers={
["Content-Type"]="application/json",Accept=
"application/json",
},
Body=d:JSONEncode{
clientId=t,
hashes=u,
},
})

if not v or type(w)~="table"or w.StatusCode~=200 or type(w.Body)~="string"then
return false
end

local x,y=pcall(function()
return d:JSONDecode(w.Body)
end)
if not x or type(y)~="table"or type(y.sources)~="table"then
return false
end

for z,A in ipairs(y.sources)do
if type(A)=="table"then
RememberScriptSourceForHash(A.scriptHash,A.source)
end
end

return true
end

local function FetchCachedScriptSources(t,u)
if type(request)~="function"then return end
if type(t)~="string"or t==""then return end
if type(u)~="table"then return end

local v={}
local w={}
local function flush()
local x=FetchCachedScriptSourceBatch(t,v)
if x then
for y,z in v do
c.sourceCacheCheckedByHash[z]=true
end
end
table.clear(v)
end

for x,y in ipairs(u)do
if(
type(y)=="string"and
y~=""and
not c.sourceCacheByHash[y]and
not c.sourceCacheCheckedByHash[y]and
not w[y]
)then
w[y]=true
table.insert(v,y)
if#v>=m then
flush()
end
end
end

flush()
end

local function ReadScriptBytecode(t)
local u,v=RunWithTimeout(o,function()
return getscriptbytecode(t)
end)
if not u or v==nil then
return false,v or"Failed to read script bytecode."
end
return true,v
end

local function TryBuiltInDecompile(t)
if type(h)~="function"then
return nil,0,"Executor built-in decompile is unavailable.",false
end

local u=os.clock()
local v,w=RunWithTimeout(p,function()
return h(t)
end)
local x=math.floor((os.clock()-u)*1000)
if not v then
local y=tostring(w or"Built-in decompile failed.")
return nil,x,y,string.find(y,"Timed out",1,true)~=nil
end
if type(w)~="string"or w==""then
return nil,x,"Built-in decompile returned no source.",false
end

return f(w),x
end

local function IsActiveMappingContext(t,u)
return(
t==c.generation and
u~=nil and
u==c.clientId
)
end

local function RefreshDecompilerPlan(t,u,v)
u=u or c.generation
v=v or c.clientId
if not IsActiveMappingContext(u,v)then return nil end
local w=os.clock()
if not t and r.expiresAt>w then
return r.providerId
end
if r.refreshToken then
local x=w+2
repeat task.wait()until not r.refreshToken or os.clock()>=x
return r.providerId
end
if type(request)~="function"then return nil end

local x={}
r.refreshToken=x

local y,z=RunWithTimeout(5,function()
return request{
Url="http://"..e.."/decompile-plan?clientId="..d:UrlEncode(v),
Method="GET",
Headers={Accept=
"application/json",
},
}
end)
if r.refreshToken~=x then return nil end
r.refreshToken=nil
if not IsActiveMappingContext(u,v)then return nil end
if not y or type(z)~="table"or z.StatusCode~=200 or type(z.Body)~="string"then
r.providerId=nil
r.expiresAt=w+0.25
return nil
end

local A,B=pcall(function()
return d:JSONDecode(z.Body)
end)
if not A or type(B)~="table"then
r.providerId=nil
r.expiresAt=w+0.25
return nil
end

r.providerId=if type(B.providerId)=="string"then B.providerId else nil
local C=math.max(0.25,math.min((tonumber(B.ttlMs)or 1000)/1000,5))
r.expiresAt=os.clock()+C
return r.providerId
end

local function ShouldUseDirectBuiltIn(t,u,v)
if t~="builtin"then return false end
if r.blockedBuiltinUntil>os.clock()then return false end
return type(h)=="function"and RefreshDecompilerPlan(false,u,v)=="builtin"
end

local function PostBuiltInObservation(t,u,v)
if not IsActiveMappingContext(u,v)then return end
local w=c.session
if not w then return end
s.revision+=1
t.clientId=v
t.providerId="builtin"
t.observationSessionId=w.id
t.observationSessionStartedAt=w.startedAt
t.observationRevision=s.revision
t.beginObservationSession=true
task.defer(function()
if not IsActiveMappingContext(u,v)then return end
pcall(request,{
Url="http://"..e.."/decompiler-observations",
Method="POST",
Headers={
["Content-Type"]="application/json",Accept=
"application/json",
},
Body=d:JSONEncode(t),
})
end)
end

local function ReportBuiltInDecompileSuccess(t,u,v)
if not IsActiveMappingContext(u,v)then return end
local w=os.clock()
if s.lastAt==nil or w-s.lastAt>2 then
s.startedAt=w
s.samples=0
end

s.lastAt=w
s.startedAt=s.startedAt or w
s.samples+=1
if w-s.startedAt<0.25 then return end
if w-s.lastReportAt<0.5 then return end
s.lastReportAt=w

local x=math.max(0.001,w-s.startedAt)
PostBuiltInObservation({
latencyMs=t,
successCount=s.samples,
throughputPerSecond=s.samples/x,
throughputWindowMs=x*1000,
throughputSamples=s.samples,
},u,v)
end

local function ReportBuiltInDecompileFailure(t,u,v,w,x)
if not IsActiveMappingContext(w,x)then return end
r.providerId=nil
r.expiresAt=0
r.blockedBuiltinUntil=os.clock()+5
if v==true then l:Reduce()end
PostBuiltInObservation({
latencyMs=u,
errorMessage=tostring(t or"Built-in decompile failed."),
timedOut=v==true,
},w,x)
end

local function RequestServerDecompile(t,u,v,w)
if type(request)~="function"then
return nil,"request function is unavailable"
end

u=if type(u)=="table"then u else{}
local x={
clientId=w,
bytecode=g(t),
builtinAvailable=type(h)=="function",
}
if type(u.builtinSource)=="string"then
x.builtinSource=u.builtinSource
end
if type(u.builtinLatencyMs)=="number"then
x.builtinLatencyMs=u.builtinLatencyMs
end
if type(u.requestedProvider)=="string"then
x.requestedProvider=u.requestedProvider
end
if type(u.disabledProviders)=="table"then
x.disabledProviders=u.disabledProviders
end

local y,z=RunWithTimeout(q,function()
return request{
Url="http://"..e.."/decompile",
Method="POST",
Headers={
["Content-Type"]="application/json",Accept=
"application/json",
},
Body=d:JSONEncode(x),
}
end)
if not y then
return nil,tostring(z)
end

if type(z)~="table"or type(z.Body)~="string"then
return nil,"Decompile server returned no response body."
end

local A,B=pcall(function()
return d:JSONDecode(z.Body)
end)
if not A or type(B)~="table"then
return nil,"Decompile server returned invalid JSON."
end

local C
if type(B.attemptedProviders)=="table"and type(B.attemptedProviders[1])=="string"then
C=B.attemptedProviders[1]
end

if B.ok==true and type(B.source)=="string"and B.source~=""then
return f(B.source),nil,false,C
end
if B.needsBuiltin==true and B.providerId=="builtin"then
return nil,nil,true,C
end

if type(B.error)=="string"and B.error~=""then
return nil,B.error,false,C
end
if type(B.attempts)=="table"then
return nil,table.concat(B.attempts,"\n\n"),false,C
end

return nil,"Decompile server failed without a detailed error.",false,C
end

local function PrepareScriptForMapping(t,u,v,w,x)
v=v or c.generation
w=w or c.clientId
local y=t:GetDebugId()
local z=GetScriptHashForInstance(t)
if u and z then
FetchCachedScriptSources(w,{z})
end

local A=z and c.sourceCacheByHash[z]or nil
if A then
return{
debugId=y,
scriptHash=z,
source=A,
}
end

local B=RefreshDecompilerPlan(false,v,w)
local C=x or B
local D=x=="builtin"
if D or ShouldUseDirectBuiltIn(C,v,w)then
return{
debugId=y,
scriptHash=z,
retryProviderId=x,
useDirectBuiltin=true,
forceDirectBuiltinRetry=D,
}
end

local E,F=ReadScriptBytecode(t)
if not E then
return nil,F
end

return{
debugId=y,
scriptHash=z,
bytecode=F,
retryProviderId=x,
}
end

local function BuildServerOptions(t,u)
local v={}
if type(t.retryProviderId)=="string"then
v.requestedProvider=t.retryProviderId
end
if type(u)=="table"then
for w,x in u do
v[w]=x
end
end
return if next(v)==nil then nil else v
end

local function TakeRetryServerOptions(t,u)
local v=BuildServerOptions(t,u)
t.retryProviderId=nil
return v
end

local function DecompileScriptSource(t,u,v,w)
v=v or c.generation
w=w or c.clientId
local x
if not u then
u,x=PrepareScriptForMapping(t,true,v,w)
end
if not u then
return nil,x or"Failed to prepare script for decompile.",nil,nil
end

if type(u.source)=="string"and u.source~=""then
return u.source,nil,u.scriptHash,u
end
if u.useDirectBuiltin==true then
local y=u.forceDirectBuiltinRetry==true or
j.CanAttemptBuiltIn(
u,
r.blockedBuiltinUntil,
os.clock()
)
if y then
u.retryProviderId=nil
u.forceDirectBuiltinRetry=nil
u.initialProviderId=u.initialProviderId or"builtin"
j.MarkBuiltInAttempted(u)
local z,A,B,C=TryBuiltInDecompile(t)
if z then
ReportBuiltInDecompileSuccess(A,v,w)
if u.scriptHash then
RememberScriptSourceForHash(u.scriptHash,z)
end
return z,nil,u.scriptHash,u
end

j.DisableBuiltIn(u)
ReportBuiltInDecompileFailure(B,A,C,v,w)
end
local z,A=k.MaterializeServerFallback(u,function()
return ReadScriptBytecode(t)
end)
if not z then
return nil,A,u.scriptHash,u
end
end

if type(u.bytecode)~="string"then
return nil,"Prepared script is missing bytecode.",u.scriptHash,u
end

local y=TakeRetryServerOptions(
u,
if u.builtinDisabled==true then{disabledProviders={"builtin"}}else nil
)
local z,A,B,C=RequestServerDecompile(
u.bytecode,
y,
v,
w
)
if not u.initialProviderId and type(C)=="string"then
u.initialProviderId=C
end
if B then
local D=j.CanAttemptBuiltIn(
u,
r.blockedBuiltinUntil,
os.clock()
)
if D then
j.MarkBuiltInAttempted(u)
local E,F,G,H=TryBuiltInDecompile(t)
if E then
ReportBuiltInDecompileSuccess(F,v,w)
z,A=RequestServerDecompile(u.bytecode,BuildServerOptions(u,{
requestedProvider="builtin",
builtinSource=E,
builtinLatencyMs=F,
}),v,w)
else
j.DisableBuiltIn(u)
ReportBuiltInDecompileFailure(G,F,H,v,w)
z,A=RequestServerDecompile(u.bytecode,BuildServerOptions(u,{
disabledProviders={"builtin"},
}),v,w)
end
else
j.DisableBuiltIn(u)
z,A=RequestServerDecompile(u.bytecode,BuildServerOptions(u,{
disabledProviders={"builtin"},
}),v,w)
end
end
if not z then
return nil,A,u.scriptHash,u
end

if u.scriptHash then
RememberScriptSourceForHash(u.scriptHash,z)
end
return z,nil,u.scriptHash,u
end

local function ResetDecompilerClient()
r.providerId=nil
r.expiresAt=0
r.refreshToken=nil
r.blockedBuiltinUntil=0
s.startedAt=nil
s.lastAt=nil
s.samples=0
s.lastReportAt=0
s.revision=0
end

return{
DecompileScriptSource=DecompileScriptSource,
FetchCachedScriptSources=FetchCachedScriptSources,
GetScriptHashForInstance=GetScriptHashForInstance,
PrepareScriptForMapping=PrepareScriptForMapping,
RefreshDecompilerPlan=RefreshDecompilerPlan,
ResetDecompilerClient=ResetDecompilerClient,
TakeRetryServerOptions=TakeRetryServerOptions,
}
end end function a.k():typeof(__modImpl())local b=a.cache.k if not b then b={c=__modImpl()}a.cache.k=b end return b.c end end do local function __modImpl()

return function(b)
local c=b.ScriptMappingPipeline
local d=b.WorkerPool
local e=b.UploadSession
local f=b.GenerateSessionGuid
local g=b.CoreGui
local h=b.CorePackages
local i=b.ScriptContext
local j=b.getnilinstances
local k=b.WorkerCount
local l=b.Concurrency
local m=b.JobStatus
local n=b.FailedResync
local o=b.UploadClient
local p=b.DecompilerClient
local q=o.EnqueueScriptSourceUpload
local r=o.IsScriptMappingTransportReady
local s=o.ResetScriptSourceUploadQueue
local t=p.DecompileScriptSource
local u=p.FetchCachedScriptSources
local v=p.GetScriptHashForInstance
local w=p.PrepareScriptForMapping
local x=p.RefreshDecompilerPlan
local y=p.ResetDecompilerClient
local z=4
local A=8
local B=256
local C

local function PublishCurrentMappingStatus()
m:Publish()
end

local function RemoveScriptFromMapping(D,E)
local F=c.jobs[D]
if E~=c.generation or not F or F.state=="removed"then return end

c.instances[D]=nil
c:SetJobState(F,"removed")
F.script=nil
F.prepared=nil
q{
kind="remove",
debugId=D,
generation=E,
attempts=0,
}
end

local function AttachScriptToMappingJob(D,E)
D.script=E
c.instances[D.debugId]=E
if D.destroyingConnection then return end
local F=D.generation
D.destroyingConnection=E.Destroying:Once(function()
RemoveScriptFromMapping(D.debugId,F)
end)
end

local function TrackScriptForMapping(D)
return c:TrackJob(D)~=nil
end

local function DeferScriptMappingUntilTransport(D,E,F,G)
local H=G or D:GetDebugId()
local I=c.jobs[H]
if F~=c.generation or not I then return end
if I.state=="mapped"or I.state=="failed"or I.state=="removed"then return end

c:SetJobState(I,"deferred")
AttachScriptToMappingJob(I,D)
I.prepared=E
end

local function RetryScriptMapping(D,E,F,G,H)
local I=H or D:GetDebugId()
local J=c.jobs[I]
if F~=c.generation or not J then return end
if J.state=="mapped"or J.state=="failed"or J.state=="removed"then return end
if string.find(tostring(G),"Timed out",1,true)then
l:Reduce()
end

J.mappingAttempts=(J.mappingAttempts or 0)+1
if J.mappingAttempts>=z then
m:MarkFailed(I,G or"Failed to prepare or decompile script source.")
return
end

c:SetJobState(J,"queued")
AttachScriptToMappingJob(J,D)
J.prepared=E
local K=math.min(2^math.max(0,J.mappingAttempts-1),A)
task.delay(K,function()
if F~=c.generation or J.generation~=F then return end
if J.state~="queued"then return end
if not r(c.clientId)then
DeferScriptMappingUntilTransport(D,E,F,I)
return
end

c.workers:QueueOperation(D,E,F,I)
end)
end

local function QueueMappedScriptSource(D,E,F,G,H)
local I=H or D:GetDebugId()
local J=c.jobs[I]
if not J then
TrackScriptForMapping(I)
J=c.jobs[I]
elseif J.state=="failed"then
TrackScriptForMapping(I)
elseif J.state=="mapped"or J.state=="awaiting_upload"or J.state=="removed"then
return false
end

local K=D:GetFullName()
AttachScriptToMappingJob(J,D)

c:SetJobState(J,"awaiting_upload")
q{
kind="source",
debugId=I,
path=K,
source=E,
scriptHash=F,
attempts=0,
generation=G,
}
return true
end

local function MapScriptSource(D,E,F,G)
if F~=c.generation then return end

local H=G or D:GetDebugId()
local I=c.jobs[H]
if not I or I.state~="queued"then return end
if not r(c.clientId)then
DeferScriptMappingUntilTransport(D,E,F,H)
return
end
if not c:TryStartMapping(I)then return end

while c.upload.bytes>=o.UploadQueueMaxBytes do
if F~=c.generation then return end
if not r(c.clientId)then
DeferScriptMappingUntilTransport(D,E,F,H)
return
end
task.wait(0.05)
end

AttachScriptToMappingJob(I,D)
local J=c.clientId
if not E then
local K
E,K=w(
D,
true,
F,
J,
I.initialProviderId
)
if not E then
RetryScriptMapping(D,nil,F,K,H)
return
end
end
I.prepared=E
local K,L,M,N=t(
D,
E,
F,
J
)
I.prepared=N
if not I.initialProviderId and N then
I.initialProviderId=N.initialProviderId
end
if not K then
RetryScriptMapping(D,N,F,L,H)
return
end
if F~=c.generation then return end
if c.jobs[H]~=I then return end
if I.state=="mapped"or I.state=="failed"or I.state=="removed"then return end
I.mappingAttempts=0
l:RecordSuccess()

QueueMappedScriptSource(D,K,M,F,H)
end

C=function(D,E,F,G,H)
if G~=c.generation or type(H)~="string"then return end
RetryScriptMapping(E,F,G,tostring(D),H)
end

c.workers=d.new{
MaxConcurrent=k,
MainCallback=MapScriptSource,
OnError=C,
}

local function GetScriptByDebugId(D)
local E=c.instances[D]
if E then
return E
end

for F,G in game:QueryDescendants"LuaSourceContainer"do
if G:IsA"Script"and G.RunContext==Enum.RunContext.Server then continue end
if G:GetDebugId()~=D then continue end

c.instances[D]=G
return G
end

for F,G in j()do
if not G:IsA"LuaSourceContainer"then continue end

if G:IsA"Script"and G.RunContext~=Enum.RunContext.Client then continue end
if G:GetDebugId()~=D then continue end

c.instances[D]=G
return G
end

return nil
end

local function RetryFailedScripts()
if not r(c.clientId)then return end

n:ProcessDue(function(D)
local E=GetScriptByDebugId(D.debugId)
if not E then
n:Defer(D)
return
end
if not n:Claim(D)then return end

AttachScriptToMappingJob(D,E)
c.workers:QueueOperation(
E,
nil,
D.generation,
D.debugId
)
end,function(D,E)
if D.state=="failed"then
n:Defer(D)
else
m:MarkFailed(
D.debugId,
"Failed to run periodic resync: "..tostring(E)
)
end
end)
end

local function StartFailedScriptResync()
n:Start(RetryFailedScripts)
end

local function IsCandidateScriptForMapping(D)
local E=(
D:IsA"Script"and(
D.RunContext==Enum.RunContext.Server or
D.RunContext==Enum.RunContext.Legacy
)
)
if E then return false end

local F=(
D.RobloxLocked or
D:IsDescendantOf(g)or
D:IsDescendantOf(h)or
D:IsDescendantOf(i)
)
if F then return false end

local G=D:GetDebugId()
if c.jobs[G]then return false end

return true
end

local function QueueScriptForMapping(D,E)
local F=D:GetDebugId()
if not TrackScriptForMapping(F)then return end
AttachScriptToMappingJob(c.jobs[F],D)

m:Publish()
local G=c.generation
if r(c.clientId)then
c.workers:QueueOperation(D,E,G,F)
else
DeferScriptMappingUntilTransport(D,E,G,F)
end
end

local function ResumeDeferredScriptMappings()
if not r(c.clientId)then return end

for D,E in c.jobs do
if E.generation==c.generation and E.state=="deferred"then
c:SetJobState(E,"queued")
c.workers:QueueOperation(E.script,E.prepared,E.generation,D)
end
end
end

local function StartScriptMapping(D)
if not r(D)then return end

c.clientId=D
x(true,c.generation,D)

if not c.descendantConnection then
c.descendantConnection=game.DescendantAdded:Connect(function(E)
if not E:IsA"LuaSourceContainer"then
return
end

if not IsCandidateScriptForMapping(E)then return end
QueueScriptForMapping(E)
end)
end

if c.initialScanRunning or c.initialScanFinished then return end
c.initialScanRunning=true
local E=c.generation


task.spawn(function()
local F={}
local G=false local
H=pcall(function()
local H={
game:QueryDescendants"LuaSourceContainer",
j()
}
local I={}

for J,K in H do
for L,M in K do
if E~=c.generation then return end
local N,O=pcall(function()
if not M:IsA"LuaSourceContainer"then return nil end
if not IsCandidateScriptForMapping(M)then return nil end
return M:GetDebugId()
end)
if not N then
continue
end
if not O then continue end
if I[O]then continue end
I[O]=true
if not TrackScriptForMapping(O)then continue end
AttachScriptToMappingJob(c.jobs[O],M)
table.insert(F,{script=M,debugId=O})
end
end

m:Publish()

local J={}
local K={}
local function flushPreparedScripts()
u(D,J)
for L,M in K do
if E~=c.generation then return end
if r(D)then
c.workers:QueueOperation(M.script,nil,E,M.debugId)
else
DeferScriptMappingUntilTransport(M.script,nil,E,M.debugId)
end
end
table.clear(J)
table.clear(K)
end

for L,M in F do
if E~=c.generation then return end
local N=v(M.script)
if N then table.insert(J,N)end
table.insert(K,M)

if#K>=B then
flushPreparedScripts()
end
if L%250==0 then task.wait()end
end
flushPreparedScripts()

G=true
end)

if E~=c.generation then return end
c.initialScanRunning=false
if H and G then
c.initialScanFinished=true
c.stateVersion+=1
PublishCurrentMappingStatus()
return
end

for I,J in F do
local K=c.jobs[J.debugId]
if c:CanDeferScanJob(K,E)then
local L,M=pcall(
DeferScriptMappingUntilTransport,
J.script,
K.prepared,
E,
J.debugId
)
if not L then
local N,O=pcall(
RetryScriptMapping,
J.script,
K.prepared,
E,
tostring(M),
J.debugId
)
if not N then
m:MarkFailed(
J.debugId,
"Scan recovery failed: "..tostring(O),
false
)
end
end
end
end
task.delay(1,function()
ResumeDeferredScriptMappings()
StartScriptMapping(D)
end)
end)
end

local function ResetScriptMappingState(D)
local E=c.descendantConnection
local F=c.generation+1
local G=e.new(
f(),
DateTime.now().UnixTimestampMillis,
F
)
c:Reset(D,G)
y()

if E then
E:Disconnect()
c.descendantConnection=nil
end

if c.workers then
c.workers:SetMaxConcurrent(c.currentWorkers)
c.workers:Reset()
end

s()
end

return{
DecompileScriptSource=t,
GetScriptByDebugId=GetScriptByDebugId,
QueueMappedScriptSource=QueueMappedScriptSource,
ResetScriptMappingState=ResetScriptMappingState,
ResumeDeferredScriptMappings=ResumeDeferredScriptMappings,
StartFailedScriptResync=StartFailedScriptResync,
StartScriptMapping=StartScriptMapping,
}
end end function a.l():typeof(__modImpl())local b=a.cache.l if not b then b={c=__modImpl()}a.cache.l=b end return b.c end end do local function __modImpl()

return function(b,c)
local d=b.LogService

c:BindToType("execute",function(e)
task.defer(function()
setthreadidentity(8)
loadstring(e.source)()
end)
end)

c:BindToTypeRaw("get-console-output",function(e)
local f=math.max(1,math.min(tonumber(e.limit)or 20,200))
local g=e.logsOrder or"NewestFirst"
local h=e.filter
local i=typeof(h)=="string"and h~=""
local j=e.summaryOnly==true

local k=d:GetLogHistory()
local l={}
local m=0
local n={}

local function matchesFilter(o)
if not i then return true end
return string.find(o.message,h,1,true)~=nil
end

local o=500
local function formatLogMessage(p)
local q=tostring(p or"")
if#q>o then
q=string.sub(q,1,o)
.."…(+"..(#q-o).." chars omitted)"
end
return q
end

if g=="NewestFirst"then
for p=#k,1,-1 do
local q=k[p]
if not matchesFilter(q)then continue end

m+=1
local r=q.messageType and q.messageType.Name or"Unknown"
n[r]=(n[r]or 0)+1
if#l<f then
table.insert(l,q)
end
end
else
for p,q in k do
if not matchesFilter(q)then continue end

m+=1
local r=q.messageType and q.messageType.Name or"Unknown"
n[r]=(n[r]or 0)+1
if#l<f then
table.insert(l,q)
end
end
end

local p={}
if j then
table.insert(p,string.format("Matched %d logs.",m))
for q,r in n do
table.insert(p,string.format("%s: %d",q,r))
end
return table.concat(p,"\n")
end

table.insert(p,string.format("Displaying %d/%d logs:",#l,m))

for q,r in l do
table.insert(p,string.format(
"[%s t=%s] %s",
r.messageType.Name,tostring(r.timestamp),
formatLogMessage(r.message)
))
end

return table.concat(p,"\n")
end)

c:BindToType("get-data-by-code",function(e)
setthreadidentity(8)
local f=table.pack(loadstring(e.source)())

return f
end)
end end function a.m():typeof(__modImpl())local b=a.cache.m if not b then b={c=__modImpl()}a.cache.m=b end return b.c end end do local function __modImpl()

return function(b,c)
local d=b.ScriptMappingPipeline
local e=b.GetScriptByDebugId
local f=b.DecompileScriptSource
local g=b.QueueMappedScriptSource

c:BindToTypeRaw("get-script-content",function(h)
local i
local j


if h.debugId then
j=e(h.debugId)
assert(j,"No live script instance found for ScriptProxy with DebugId: "..tostring(h.debugId))
else
setthreadidentity(8)
j=loadstring(h.source)()

assert(typeof(j)=="Instance","Script instance is not an instance.")
assert(j:IsA"LuaSourceContainer","Script instance is not a LuaSourceContainer (Script, LocalScript, or ModuleScript).")
assert(not(j:IsA"Script"and j.RunContext==Enum.RunContext.Server),"Script instance is a Server Script.")
end

local k
i,_,k=f(
j,
nil,
d.generation,
d.clientId
)
assert(i,"Failed to decompile script.")

local l=j:GetDebugId()
local m=d.jobs[l]
if d.clientId and(not m or m.state~="mapped")then
g(
j,
i,
k,
d.generation,
l
)
end


local n={}
local o=1
local p=#i
while o<=p do
local q=i:find("\n",o,true)
if q then
table.insert(n,i:sub(o,q-1))
o=q+1
else
table.insert(n,i:sub(o))
break
end
end

local q=#n
local r=math.max(1,math.min(tonumber(h.maxLines)or 200,2000))
local s=h.startLine and math.max(1,math.min(h.startLine,q))or 1
local t=h.endLine and math.max(s,math.min(h.endLine,q))or q
local u=math.min(t,s+r-1)

local v={}
for w=s,u do
table.insert(v,n[w])
end

local w=""
if u<t then
w="\n-- Output truncated to "..r.." lines. Rerun with startLine="..(u+1).." or a tighter range to continue."
end

return"-- Lines "..s.."-"..u.." of "..q.."\n"..table.concat(v,"\n")..w
end)
end end function a.n():typeof(__modImpl())local b=a.cache.n if not b then b={c=__modImpl()}a.cache.n=b end return b.c end end do local function __modImpl()

return function(b,c)
local d=b.MarketplaceService
local e=b.RobloxReplicatedStorage

c:BindToType("search-instances",function(f)
local g=loadstring("return "..f.root)()
local h=g:QueryDescendants(f.selector)

local i=math.max(1,math.min(tonumber(f.limit)or 20,100))
local j={}

for k,l in h do
if k>i then break end

local m=l.Name
pcall(function()m=l:GetFullName()end)

table.insert(j,{
Name=l.Name,
ClassName=l.ClassName,
Path=m,
DebugId=l:GetDebugId()
})
end

return{
count=#h,
limited=#h>i,
results=j
}
end)

c:BindToType("get-game-info",function(f)
local g=d:GetProductInfo(game.PlaceId)

local h={
PlaceId=game.PlaceId,
GameId=game.GameId,
PlaceVersion=game.PlaceVersion,
PlaceName=g.Name,
Creator=g.Creator.Name,
CreatorType=tostring(g.Creator.CreatorType),
CreatorId=g.Creator.CreatorTargetId,
JobId=game.JobId,
ServerType=e.GetServerType:InvokeServer()
}



if f.includeDescription==true then
h.PlaceDescription=g.Description
end

return h
end)

c:BindToType("get-descendants-tree",function(f)
local g=loadstring("return "..f.root)()
assert(typeof(g)=="Instance","Root path did not resolve to a valid Instance.")

local h=math.max(0,math.min(tonumber(f.maxDepth)or 2,5))
local i=math.max(1,math.min(tonumber(f.maxChildren)or 20,30))
local j=f.classFilter or""
local k=j~=""
local l=f.summaryOnly==true
local m=300
local n=m
local o=false

if l then
local p={}
local q=0
local r=0

local function walk(s,t)
if t>h then
return
end

for u,v in s:GetChildren()do
q+=1
if not k or v:IsA(j)then
r+=1
p[v.ClassName]=(p[v.ClassName]or 0)+1
end
if t<h then
walk(v,t+1)
end
end
end

walk(g,1)

return{
Root={
Name=g.Name,
ClassName=g.ClassName,
ChildCount=#g:GetChildren(),
},
MaxDepth=h,
ClassFilter=if k then j else nil,
VisitedDescendants=q,
MatchedDescendants=r,
ClassCounts=p,
}
end

local function buildTree(p,q)
if q>h then
return nil
end

local r=p:GetChildren()
local s={}
local t=0
local u=#r

for v,w in r do
if t>=i then break end
if n<=0 then
o=true
break
end

if k and not w:IsA(j)then


if q<h then
local x=buildTree(w,q+1)
if x and x.Children and#x.Children>0 then
table.insert(s,x)
t+=1
end
end
continue
end

n-=1

local x={
Name=w.Name,
ClassName=w.ClassName,
ChildCount=#w:GetChildren()
}

if q<h and x.ChildCount>0 then
local y=buildTree(w,q+1)
if y then
x.Children=y.Children
end
end

table.insert(s,x)
t+=1
end

return{
Name=p.Name,
ClassName=p.ClassName,
ChildCount=u,
TruncatedAt=if t<u then t else nil,
Children=s
}
end

local p=buildTree(g,0)
if o and typeof(p)=="table"then
p.Note="Output capped at "..m.." nodes. Narrow with classFilter, lower maxDepth, or summaryOnly=true."
end
return p
end)
end end function a.o():typeof(__modImpl())local b=a.cache.o if not b then b={c=__modImpl()}a.cache.o=b end return b.c end end do local function __modImpl()

return function(b,c)
c:BindToType("ensure-remote-spy",function(d)
if getgenv().Cobalt then
return{
status="already_loaded",
message="Cobalt remote spy is already running."
}
end


local e,f=pcall(function()
loadstring(game:HttpGet"https://github.com/notpoiu/cobalt/releases/latest/download/Cobalt.luau")()
end)

if not e then
error("Failed to load Cobalt: "..tostring(f))
end


local g=os.clock()
while not getgenv().Cobalt and os.clock()-g<10 do
task.wait(0.1)
end

assert(getgenv().Cobalt,"Cobalt loaded but failed to initialize within 10 seconds.")

return{
status="loaded",
message="Cobalt remote spy loaded successfully."
}
end)

c:BindToType("get-remote-spy-logs",function(d)
local e=getgenv().Cobalt
assert(e and e.shared and e.shared.Logs,"Cobalt remote spy is not loaded. Call ensure-remote-spy first.")

local f=d.direction or"Both"
local g=d.remoteNameFilter or""
local h=math.max(1,math.min(tonumber(d.limit)or 10,100))
local i=math.max(0,math.min(tonumber(d.maxCallsPerRemote)or 2,20))
local j=d.summaryOnly==true
local k=g~=""

local function ProcessLogs(l,m)
local n={}

for o,p in l do
if typeof(o)~="Instance"then continue end
if#n>=h then break end

local q=""
local r=""
pcall(function()
q=o.Name
r=o.ClassName
end)


if k and not string.find(string.lower(q),string.lower(g),1,true)then
continue
end


local s={}
local t=#p.Calls
local u=math.max(1,t-i+1)

if not j then
for v=u,t do
local w=p.Calls[v]
if not w then continue end

table.insert(s,{
Index=v,
Arguments=w.Arguments,
Origin=w.Origin,
IsExecutor=w.IsExecutor or false,
IsActor=w.IsActor or false,
Line=w.Line,
})
end
end

table.insert(n,{
RemoteName=q,
RemoteClass=r,
Direction=m,
Method=p.Method,
TotalCalls=t,
Ignored=p.Ignored,
Blocked=p.Blocked,
RecentCalls=if j then nil else s,
})
end

return n
end

local l={}

if f=="Outgoing"or f=="Both"then
local m=ProcessLogs(e.shared.Logs.Outgoing,"Outgoing")
for n,o in m do
table.insert(l,o)
end
end

if f=="Incoming"or f=="Both"then
local m=ProcessLogs(e.shared.Logs.Incoming,"Incoming")
for n,o in m do
table.insert(l,o)
end
end


table.sort(l,function(m,n)
return m.TotalCalls>n.TotalCalls
end)


if#l>h then
local m={}
for n=1,h do
m[n]=l[n]
end
l=m
end

return{
count=#l,
results=l
}
end)
end end function a.p():typeof(__modImpl())local b=a.cache.p if not b then b={c=__modImpl()}a.cache.p=b end return b.c end end do local function __modImpl()

return function(b,c)
c:BindToType("clear-remote-spy-logs",function(d)
local e=getgenv().Cobalt
assert(e and e.shared and e.shared.ClearLogs,"Cobalt remote spy is not loaded. Call ensure-remote-spy first.")

e.shared.ClearLogs()

return{
status="cleared",
message="All remote spy logs have been cleared."
}
end)

c:BindToType("block-remote",function(d)
local e=getgenv().Cobalt
assert(e and e.shared and e.shared.Logs,"Cobalt remote spy is not loaded. Call ensure-remote-spy first.")

local f=d.remoteName
local g=d.direction
local h=d.shouldBlock

local i=e.shared.Logs[g]
assert(i,"Invalid direction: "..tostring(g))

for j,k in i do
if typeof(j)~="Instance"then continue end

local l=""
pcall(function()l=j.Name end)

if l==f then
if h and not k.Blocked then
k:Block()
elseif not h and k.Blocked then
k:Block()
end

return{
status="success",
message=(h and"Blocked"or"Unblocked").." remote: "..f,
blocked=k.Blocked
}
end
end

error("Remote not found: "..f.." in "..g.." logs. Make sure the remote has been logged at least once.")
end)

c:BindToType("ignore-remote",function(d)
local e=getgenv().Cobalt
assert(e and e.shared and e.shared.Logs,"Cobalt remote spy is not loaded. Call ensure-remote-spy first.")

local f=d.remoteName
local g=d.direction
local h=d.shouldIgnore

local i=e.shared.Logs[g]
assert(i,"Invalid direction: "..tostring(g))

for j,k in i do
if typeof(j)~="Instance"then continue end

local l=""
pcall(function()l=j.Name end)

if l==f then
if h and not k.Ignored then
k:Ignore()
elseif not h and k.Ignored then
k:Ignore()
end

return{
status="success",
message=(h and"Ignoring"or"Unignored").." remote: "..f,
ignored=k.Ignored
}
end
end

error("Remote not found: "..f.." in "..g.." logs. Make sure the remote has been logged at least once.")
end)




c:BindToType("remote-spy",function(d)
c.Callbacks["ensure-remote-spy"]{}

local e=d.operation
if e=="status"then
local f=getgenv().Cobalt
local function CountLogs(g)
local h=0
if typeof(g)~="table"then return h end
for i in g do
h+=1
end
return h
end

return{
status="loaded",
outgoingRemotes=CountLogs(f.shared and f.shared.Logs and f.shared.Logs.Outgoing),
incomingRemotes=CountLogs(f.shared and f.shared.Logs and f.shared.Logs.Incoming),
}
elseif e=="list"then
return c.Callbacks["get-remote-spy-logs"]{
direction=d.direction,
remoteNameFilter=d.nameFilter,
limit=d.limit,
maxCallsPerRemote=d.maxCallsPerRemote,
summaryOnly=d.summaryOnly,
}
elseif e=="clear"then
return c.Callbacks["clear-remote-spy-logs"]{}
elseif e=="block"or e=="unblock"then
return c.Callbacks["block-remote"]{
remoteName=d.remoteName,
direction=d.direction,
shouldBlock=e=="block",
}
elseif e=="ignore"or e=="unignore"then
return c.Callbacks["ignore-remote"]{
remoteName=d.remoteName,
direction=d.direction,
shouldIgnore=e=="ignore",
}
end

error("Invalid remote-spy operation: "..tostring(e))
end)
end end function a.q():typeof(__modImpl())local b=a.cache.q if not b then b={c=__modImpl()}a.cache.q=b end return b.c end end do local function __modImpl()

return function(b,c)
local d=b.VirtualInputManager

c:BindToType("type-text-box",function(e)
local f=e.path
local g=e.string or e.text
local h=e.enter
local i=e.useKeyPress

local j
if typeof(f)=="string"then
j=loadstring("return "..f)()
else
j=f
end

assert(typeof(j)=="Instance","Path did not resolve to a valid Instance.")
assert(j:IsA"TextBox","Resolved Instance is not a TextBox.")

j:CaptureFocus()
task.wait(0.05)

if i then
local k=pcall(function()
for k=1,#g do
d:SendTextInput(g:sub(k,k),nil,game)
task.wait(0.01)
end
end)

if not k and type(keypress)=="function"then
for l=1,#g do
local m=g:sub(l,l):upper()
local n=m:byte()
if n then
keypress(n)
task.wait(0.01)
if type(keyrelease)=="function"then
keyrelease(n)
end
end
end
end
else
j.Text=g
end

if h then
if i then
if type(keypress)=="function"then
keypress(0x0D)
task.wait(0.01)
if type(keyrelease)=="function"then
keyrelease(0x0D)
end
else
pcall(function()
d:SendKeyEvent(true,Enum.KeyCode.Return,false,game)
task.wait(0.01)
d:SendKeyEvent(false,Enum.KeyCode.Return,false,game)
end)
end
end
j:ReleaseFocus(true)
else
j:ReleaseFocus(false)
end

return{
status="success",
message="Successfully typed into TextBox."
}
end)

c:BindToType("click-button",function(e)
local f=e.path
local g=e.Action or e.action

local h
if typeof(f)=="string"then
h=loadstring("return "..f)()
else
h=f
end

assert(typeof(h)=="Instance","Path did not resolve to a valid Instance.")
assert(h:IsA"GuiButton","Resolved Instance is not a GuiButton (e.g., TextButton or ImageButton).")
assert(typeof(firesignal)=="function","Your executor does not support 'firesignal', which is required for this command.")

local i={"Activated","MouseButton1Down","MouseButton2Down","MouseButton1Click","MouseButton2Click"}

if g then
assert(table.find(i,g),"Invalid action provided. Valid actions are: "..table.concat(i,", "))
firesignal(h[g])
else
for j,k in pairs(i)do
pcall(function()firesignal(h[k])end)
end
end

return{
status="success",
message="Successfully fired click signals on Button."
}
end)
end end function a.r():typeof(__modImpl())local b=a.cache.r if not b then b={c=__modImpl()}a.cache.r=b end return b.c end end do local function __modImpl()

return function(b)
local c=b.CreateBridge
local d=b.WaitForBridgeClientId
local e=b.ScriptMappingPipeline
local f=b.StartUploadQueue
local g=b.PublishScriptMappingStatus
local h=b.ResetScriptMappingState
local i=b.StartScriptMapping
local j=b.StartFailedScriptResync
local k=b.ResumeDeferredScriptMappings

while true do
local l,m=pcall(c)

if not l then
task.wait(3)
continue
end

local n=d(m)
if n then
e.bridge=m
f()

if e.clientId~=n then
h(n)
end

if not getgenv().DisableInitialScriptDecompMapping then
i(n)
j()
k()
g()
else
e.clientId=n
e.disabled=true
e.stateVersion+=1
g()
end
end

local o={a.m()
,a.n()
,a.o()
,a.p()
,a.q()
,a.r()
,
}
for p,q in o do
q(b,m)
end

m:WaitForDisconnect()
m:Destroy()

if e.bridge==m then
e.bridge=nil
end
task.wait(1)
end
end end function a.s():typeof(__modImpl())local b=a.cache.s if not b then b={c=__modImpl()}a.cache.s=b end return b.c end end end




if getgenv().MCP_Loaded==true then
return
end

getgenv().MCP_Loaded=true

local b=getgenv().BridgeURL or getgenv().bridgeurl or...or"localhost:16384"
getgenv().BridgeURL=b
getgenv().bridgeurl=b


if not game:IsLoaded()then
game.Loaded:Wait()
end


local c=cloneref or function(c)return c end

local d:RobloxReplicatedStorage=c(game:GetService"RobloxReplicatedStorage")
local e:VirtualInputManager=c(Instance.new"VirtualInputManager")
local f:MarketplaceService=c(game:GetService"MarketplaceService")
local g:CoreGui=c(game:GetService"CoreGui")
local h:CorePackages=c(game:GetService"CorePackages")
local i:ScriptContext=c(game:GetService"ScriptContext")
local j:HttpService=c(game:GetService"HttpService")
local k:LogService=c(game:GetService"LogService")
local l:Players=c(game:GetService"Players")



local m
do




local n='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'


m=base64encode or function(o)
return((o:gsub('.',function(p)
local q,r='',p:byte()
for s=8,1,-1 do q=q..(r%2^s-r%2^(s-1)>0 and'1'or'0')end
return q
end)..'0000'):gsub('%d%d%d?%d?%d?%d?',function(p)
if(#p<6)then return''end
local q=0
for r=1,6 do q=q+(p:sub(r,r)=='1'and 2^(6-r)or 0)end
return n:sub(q+1,q+1)
end)..({'','==','='})[#o%3+1])
end
end



local n=type(getscripthash)=="function"and getscripthash or nil
local o=type(decompile)=="function"and decompile or nil

local p=loadstring(game:HttpGet"https://raw.githubusercontent.com/chadhyatt/LuaEncode/refs/heads/master/src/LuaEncode.lua")()




local q=8
local r=60
local s=500

local function SanitizeForOutput(t,u,v)
u=u or 0
local w=typeof(t)

if w=="Instance"then
local x,y=pcall(function()return t:GetFullName()end)
return x and y or tostring(t)
elseif w=="string"then
if#t>s then
return string.sub(t,1,s)
.."…(+"..(#t-s).." chars omitted)"
end
return t
elseif w=="number"or w=="boolean"or w=="nil"then
return t
elseif w~="table"then

return tostring(t)
end

if u>=q then
return"<table: max depth reached>"
end

v=v or{}
if v[t]then
return"<cyclic table>"
end
v[t]=true

local x={}
local y=0
local z=0
for A,B in pairs(t)do
if y>=r then
z+=1
continue
end
y+=1
local C=A
if typeof(A)~="string"and typeof(A)~="number"then
C=tostring(A)
end
x[C]=SanitizeForOutput(B,u+1,v)
end
if z>0 then
x.__omitted=z.." more entries omitted"
end

v[t]=nil
return x
end



local function StripDecompilerBanner(t)
if typeof(t)~="string"then return t end
return(string.gsub(t,"^%s*%-%-[^\n]*[Dd]ecompiled[^\n]*\n","",1))
end

local t=getnilinstances or function()return{}end


local u=(
typeof(WebSocket)~="nil"and
typeof(WebSocket.connect)=="function"
)and(getgenv().DisableWebSocket~=true)


local function GenerateSessionGuid()
local v,w=pcall(function()
return j:GenerateGUID(false)
end)
if v and type(w)=="string"and w~=""then
return w
end
return tostring(os.clock()).."-"..tostring(math.random(1,1000000000))
end

local function GetClientIdentityKey()
local v=l.LocalPlayer
return table.concat({
tostring(game.PlaceId or 0),
tostring(game.JobId or""),
tostring(v and v.UserId or 0),
},":")
end

local function GetStableClientSessionId()
local v=GetClientIdentityKey()
if type(getgenv().MCP_ClientSessionId)~="string"or getgenv().MCP_ClientIdentityKey~=v then
getgenv().MCP_ClientSessionId=GenerateSessionGuid()
getgenv().MCP_ClientIdentityKey=v
end
return getgenv().MCP_ClientSessionId
end

local function GetRegistrationInfo()
local v=l.LocalPlayer
local w="Unknown"
pcall(function()
local x=f:GetProductInfo(game.PlaceId)
w=x.Name
end)
return{
type="register",
username=v and v.Name or"Unknown",
userId=v and v.UserId or 0,
placeId=game.PlaceId,
jobId=game.JobId,
placeName=w,
sessionId=GetStableClientSessionId(),
}
end


local v=a.a(){
HttpService=j,
BridgeURL=b,
WebSocketAvailable=u,
GetRegistrationInfo=GetRegistrationInfo,
SanitizeForOutput=SanitizeForOutput,
LuaEncode=p,
}
local w=v.CreateBridge


local x=a.b()
local y=a.c()
local z=a.d()
local A=a.e()
local B=a.f()
local C=y.new()
local D=math.max(
1,
math.min(math.floor(tonumber(getgenv().MCP_ScriptMappingWorkers)or 24),64)
)
local E=a.g().new(
C,
D
)
local F=math.max(
5,
math.min(tonumber(getgenv().MCP_FailedScriptResyncInterval)or 30,600)
)
local G=a.h().new(C,{
IntervalSeconds=F,
MaxDelaySeconds=math.max(F,300),
BatchSize=math.max(
1,
math.min(math.floor(tonumber(getgenv().MCP_FailedScriptResyncBatchSize)or 8),32)
),
})
local H=a.i().new(
C,
G
)
local I=a.j(){
ScriptMappingPipeline=C,
HttpService=j,
BridgeURL=b,
JobStatus=H,
}
local J=a.k(){
ScriptMappingPipeline=C,
HttpService=j,
BridgeURL=b,
StripDecompilerBanner=StripDecompilerBanner,
base64_encode=m,
BuiltInDecompile=o,
GetScriptHash=n,
DecompilerAttemptState=A,
PreparedScript=B,
Concurrency=E,
}
local K=a.l(){
ScriptMappingPipeline=C,
WorkerPool=x,
UploadSession=z,
GenerateSessionGuid=GenerateSessionGuid,
CoreGui=g,
CorePackages=h,
ScriptContext=i,
getnilinstances=t,
WorkerCount=D,
Concurrency=E,
JobStatus=H,
FailedResync=G,
UploadClient=I,
DecompilerClient=J,
}
local L=I.StartUploadQueue
local function PublishScriptMappingStatus()
H:Publish()
end
local M=K.StartScriptMapping
local N=K.StartFailedScriptResync
local O=K.ResetScriptMappingState
local P=K.ResumeDeferredScriptMappings
local Q=K.GetScriptByDebugId
local R=K.QueueMappedScriptSource
local S=K.DecompileScriptSource

local function WaitForBridgeClientId(T)
local U=os.clock()+5
repeat
if T.ClientId then
return T.ClientId
end
if not T.Connected then
return nil
end
task.wait(0.05)
until os.clock()>U

return nil
end a.s()

{
CreateBridge=w,
WaitForBridgeClientId=WaitForBridgeClientId,
ScriptMappingPipeline=C,
StartUploadQueue=L,
PublishScriptMappingStatus=PublishScriptMappingStatus,
ResetScriptMappingState=O,
StartScriptMapping=M,
StartFailedScriptResync=N,
ResumeDeferredScriptMappings=P,
GetScriptByDebugId=Q,
DecompileScriptSource=S,
QueueMappedScriptSource=R,
LogService=k,
MarketplaceService=f,
RobloxReplicatedStorage=d,
VirtualInputManager=e,
LuaEncode=p,
}