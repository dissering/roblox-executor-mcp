local a={cache={}::any}do do local function __modImpl()local b={}

function b.GetEnvironment(c)
if type(c.getgenv)=="function"then
local d,e=pcall(c.getgenv)
if d and type(e)=="table"then return e,"getgenv"end
end
if type(c._G)=="table"then return c._G,"_G"end
return c,"script"
end

function b.new(c)
c=c or getfenv(0)
local d,e=b.GetEnvironment(c)
local function lookup(f)
local g=d[f]
if g==nil then g=c[f]end
return g
end
local function nested(f,g)
local h=lookup(f)
return type(h)=="table"and h[g]or nil
end
local function firstFunction(...)
for f=1,select("#",...)do
local g=select(f,...)
if type(g)=="function"then return g end
end
return nil
end

local f=firstFunction(lookup"request",lookup"http_request",nested("syn","request"),nested("http","request"))
local g=firstFunction(lookup"setthreadidentity",lookup"setidentity",nested("syn","set_thread_identity"))
local h=firstFunction(lookup"cloneref")
local i=firstFunction(lookup"getnilinstances")
local j=firstFunction(nested("WebSocket","connect"),nested("websocket","connect"))
local k={
name="Unknown",version="",environment=e,
available={
getgenv=e=="getgenv",request=f~=nil,websocket=j~=nil,
setthreadidentity=g~=nil,cloneref=h~=nil,
getnilinstances=i~=nil,
},
}
for l,m in{"loadstring","decompile","getscriptbytecode","getconnections","firesignal","hookmetamethod","hookfunction","getnamecallmethod","newcclosure","checkcaller"}do
k.available[m]=type(lookup(m))=="function"
end
local l=firstFunction(lookup"identifyexecutor",lookup"getexecutorname")
if l then
local m,n,o=pcall(l)
if m then
k.name=tostring(n or"Unknown")
k.version=tostring(o or"")
end
end

local m={Environment=d,Info=k,ConnectWebSocket=j}

function m.Request(n)
assert(f,"This executor needs request, http_request, syn.request or http.request to connect to MCP.")
local o=f(n)
assert(type(o)=="table","Executor HTTP request returned no response table.")
return{
StatusCode=tonumber(o.StatusCode or o.Status or o.status_code or o.status),
Body=o.Body or o.body,
Headers=o.Headers or o.headers or{},
}
end

function m.SetThreadIdentity(n)
if not g then return false end
local o=pcall(g,n or 8)
if not o then k.available.setthreadidentity=false end

return o
end

function m.CloneReference(n)
if h then
local o,p=pcall(h,n)
if o and p~=nil then return p end
k.available.cloneref=false
end
return n
end

function m.GetNilInstances()
if i then
local n,o=pcall(i)
if n and type(o)=="table"then return o end
k.available.getnilinstances=false
end
return{}
end

function m.RequireRemoteSpySupport()
local n={}
for o,p in{"hookmetamethod","hookfunction","getnamecallmethod","newcclosure","checkcaller"}do
if not k.available[p]then table.insert(n,p)end
end
assert(#n==0,"Remote spying is unavailable on this executor: missing "..table.concat(n,", ")..". Execution, inspection and decompilation remain available.")
end

return m
end

return b end function a.a():typeof(__modImpl())local b=a.cache.a if not b then b={c=__modImpl()}a.cache.a=b end return b.c end end do local function __modImpl()

return function(b)
local c=b.Request or request
local d=b.ConnectWebSocket
local e=b.HttpService
local f=b.BridgeURL
local g=b.WebSocketAvailable
local h=b.GetRegistrationInfo
local i=b.SanitizeForOutput
local j=b.LuaEncode


local k={};do
k.__index=k

function k.BindToType(l,m,n)
l.Callbacks[m]=n
end

function k.BindToTypeRaw(l,m,n)
l.Callbacks[m]=n
l.RawCallbacks=l.RawCallbacks or{}
l.RawCallbacks[m]=true
end

function k.CreateAlias(l,m,n)
for o,p in n do
l.Callbacks[p]=l.Callbacks[m]
if l.RawCallbacks and l.RawCallbacks[m]then
l.RawCallbacks[p]=true
end
end
end

function k.HandleMessage(l,m)
if l.Callbacks[m.type]then
local n,o=pcall(function()
return l.Callbacks[m.type](m)
end)

if n and o==nil then
return nil
end

if not n then
return l:FormatResponse(o,m.id,true)
end

if l.RawCallbacks and l.RawCallbacks[m.type]then
return{
output=tostring(o),
success=true,
id=m.id
}
end

return l:FormatResponse(o,m.id,false)
end
return nil
end

function k.FormatResponse(l,m,n,o)
if o then
return{
error=tostring(m),
success=false,
id=n
}
end

local p=i(m)
if typeof(p)~="table"then
p={p}
end

return{
output=j(p,{
Prettify=false
}),
success=true,
id=n
}
end

function k.IsAlive(l)
local m,n=pcall(function()
local m
local n=task.spawn(function()
local n,o=pcall(c,{
Url="http://"..f,
Method="GET"
})

if n then
m=o
end
end)

local o=os.clock()
repeat task.wait(0.05)until m~=nil or os.clock()-o>5

if m==nil then
task.cancel(n)
return false
end


if m.StatusCode==426 or m.StatusCode==200 then
return true
end

return false
end)

if not m then
return false
end

return n
end
end


local l=setmetatable({},{__index=k});do
l.__index=l

function l.new()
local m=setmetatable({},l)


local n=0.5
local o=5
local p=10
local q=0

while not m:IsAlive()do
q+=1
if q>=p then
error("Failed to connect to bridge server after "..p.." attempts")
end
task.wait(n)
n=math.min(n*1.5,o)
end


local r
local s=task.spawn(function()
local s,t=pcall(function()
return d("ws://"..f)
end)
if s then
r=t
end
end)

local t=os.clock()
repeat task.wait(0.05)until r~=nil or os.clock()-t>5

if r==nil then
task.cancel(s)
error"WebSocket connection timed out after 5 seconds"
end

m.WebSocket=r
m.Connected=true
m.Callbacks={}
m.ClientId=nil


m.WebSocket:Send(e:JSONEncode(h()))

m.AliveThread=task.spawn(function()
local u=0
while task.wait(1)do
if not m.Connected then
continue
end

if m:IsAlive()then
u=0
continue
end

u+=1
if u<3 then
continue
end

m.Connected=false
break
end

pcall(function()
m.WebSocket:Close()
end)
end)


m.WebSocket.OnMessage:Connect(function(u)
local v=e:JSONDecode(u)


if v.type=="registered"then
m.ClientId=v.clientId
return
end

local w=m:HandleMessage(v)
if w then
m.WebSocket:Send(e:JSONEncode(w))
end
end)


m.WebSocket.OnClose:Connect(function()
m.Connected=false
end)

return m
end

function l.WaitForDisconnect(m)
while m.Connected do
task.wait(0.1)
end
end
end


local m=setmetatable({},{__index=k});do
m.__index=m

function m.new()
local n=setmetatable({},m)


local o=0.5
local p=5
local q=10
local r=0

while not n:IsAlive()do
r+=1
if r>=q then
error("Failed to connect to bridge server after "..q.." attempts")
end
task.wait(o)
o=math.min(o*1.5,p)
end

n.Connected=true
n.Callbacks={}
n.PollInterval=0.1
n.ClientId=nil


pcall(function()
local s=c{
Url="http://"..f.."/register",
Method="POST",
Headers={["Content-Type"]="application/json"},
Body=e:JSONEncode(h()),
}
if s.StatusCode==200 and s.Body then
local t=e:JSONDecode(s.Body)
n.ClientId=t.clientId
end
end)


n.PollThread=task.spawn(function()
local s=0

while n.Connected do
local t=false local
u=pcall(function()
local u="http://"..f.."/poll"
if n.ClientId then
u=u.."?clientId="..n.ClientId
end
local v=c{
Url=u,
Method="GET"
}


if v.StatusCode~=204 and v.StatusCode~=200 then
s+=1
if s>=3 then
n.Connected=false
end

return
end

s=0


if v.Body and v.Body~=""then
local w=e:JSONDecode(v.Body)
local x={}
if typeof(w)=="table"and w.type==nil and#w>0 then
x=w
elseif typeof(w)=="table"and w.type~=nil then
x={w}
end

for y,z in ipairs(x)do
t=true
task.spawn(function()
local A=n:HandleMessage(z)
if A==nil then return end


c{
Url="http://"..f.."/respond",
Method="POST",
Headers={
["Content-Type"]="application/json"
},
Body=e:JSONEncode(A)
}
end)
end
end
end)

if not u then
s+=1
if s>=3 then
n.Connected=false
end
end

if not t then
task.wait(n.PollInterval)
end
end
end)

return n
end

function m.WaitForDisconnect(n)
while n.Connected do
task.wait(0.1)
end
end
end


local function CreateBridge()
if g then
local n,o=pcall(function()
return l.new()
end)

if n then
return o
end
end

return m.new()
end

return{
CreateBridge=CreateBridge,
}
end end function a.b():typeof(__modImpl())local b=a.cache.b if not b then b={c=__modImpl()}a.cache.b=b end return b.c end end do local function __modImpl()

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

return b end function a.c():typeof(__modImpl())local b=a.cache.c if not b then b={c=__modImpl()}a.cache.c=b end return b.c end end do local function __modImpl()

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

return b end function a.d():typeof(__modImpl())local b=a.cache.d if not b then b={c=__modImpl()}a.cache.d=b end return b.c end end do local function __modImpl()

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

return b end function a.e():typeof(__modImpl())local b=a.cache.e if not b then b={c=__modImpl()}a.cache.e=b end return b.c end end do local function __modImpl()

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

return b end function a.f():typeof(__modImpl())local b=a.cache.f if not b then b={c=__modImpl()}a.cache.f=b end return b.c end end do local function __modImpl()

local b=a.f()

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

return c end function a.g():typeof(__modImpl())local b=a.cache.g if not b then b={c=__modImpl()}a.cache.g=b end return b.c end end do local function __modImpl()

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

return b end function a.h():typeof(__modImpl())local b=a.cache.h if not b then b={c=__modImpl()}a.cache.h=b end return b.c end end do local function __modImpl()

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

return b end function a.i():typeof(__modImpl())local b=a.cache.i if not b then b={c=__modImpl()}a.cache.i=b end return b.c end end do local function __modImpl()

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

return b end function a.j():typeof(__modImpl())local b=a.cache.j if not b then b={c=__modImpl()}a.cache.j=b end return b.c end end do local function __modImpl()

return function(b)
local c=b.Request or request
local d=b.ScriptMappingPipeline
local e=b.HttpService
local f=b.BridgeURL
local g=b.JobStatus
local h=64
local i=8388608
local j=0.5
local k=5
local l=8

local function IsScriptMappingTransportReady(m)
return(
d.bridge~=nil and
d.bridge.Connected==true and
d.bridge.ClientId~=nil and
d.bridge.ClientId==m
)
end

local function UploadScriptSourceBatch(m,n)
if not m then return false end
if not IsScriptMappingTransportReady(m)then return false end
local o=d.generation
local p=d.session
if not p then return false end

local q={}
local r={}
for s,t in n or{}do
if t.kind=="remove"then
table.insert(r,t.debugId)
else
table.insert(q,{
debugId=t.debugId,
path=t.path,
source=t.source,
scriptHash=t.scriptHash,
})
end
end

local s=#q
local t=math.min(d.total,d.processed+s)
local u=d:IsFinished(t)
local v=p:NextRevision()

local w,x=pcall(c,{
Url="http://"..f.."/script-sources",
Method="POST",
Headers={
["Content-Type"]="application/json"
},
Body=e:JSONEncode{
clientId=m,
scripts=q,
removedScriptIds=r,
hasFinishedMapping=u,
sourcesToMap=d.total,
processedSources=t,
skippedSources=d.skipped,
mappingSessionId=p.id,
mappingSessionStartedAt=p.startedAt,
mappingRevision=v,
beginMappingSession=not p.started,
}
})

if not w or not x or x.StatusCode~=200 then return false,v end

if(
not d:IsActiveSession(p,o,m)
)then
return false,v,"stale_session"
end

local y=v
if type(x.Body)=="string"and x.Body~=""then
local z,A=pcall(function()
return e:JSONDecode(x.Body)
end)
if z and type(A)=="table"and type(A.acceptedMappingRevision)=="number"then
y=A.acceptedMappingRevision
end
end
if y~=v then return false,v end

p:MarkStarted()
return true,v
end

local function EnqueueScriptSourceUpload(m)
m.queuedBytes=if type(m.source)=="string"then#m.source else 0
d.upload.tail+=1
d.upload.queue[d.upload.tail]=m
d.upload.bytes+=m.queuedBytes
end

local function DequeueScriptSourceUpload()
if d.upload.head>d.upload.tail then return nil end
local m=d.upload.queue[d.upload.head]
d.upload.queue[d.upload.head]=nil
d.upload.head+=1
if m then d.upload.bytes=math.max(0,d.upload.bytes-(m.queuedBytes or 0))end
return m
end

local function ResetScriptSourceUploadQueue()
d.upload.queue={}
d.upload.head=1
d.upload.tail=0
d.upload.bytes=0
end

local function StartUploadQueue()
if d.upload.thread then return end

d.upload.thread=task.spawn(function()
while true do
if not IsScriptMappingTransportReady(d.clientId)then
task.wait(j)
continue
end
if d.upload.head>d.upload.tail then
if d.statusDirty then
local m=d.stateVersion
local n=UploadScriptSourceBatch(
d.clientId,
{}
)
if n and d.stateVersion==m then
d.statusDirty=false
end
end
task.wait(j)
continue
end

local m={}
local n=0
while d.upload.head<=d.upload.tail and#m<h do
local o=d.upload.queue[d.upload.head]
local p=if o and type(o.source)=="string"then#o.source else 0
if#m>0 and n+p>i then break end

local q=DequeueScriptSourceUpload()
if not q then continue end
local r=d.jobs[q.debugId]
local s=q.generation==d.generation and r~=nil
local t=s and(
(q.kind=="source"and r.state=="awaiting_upload")or
(q.kind=="remove"and r.state=="removed")
)
if t then
table.insert(m,q)
n+=p
end
end
if#m==0 then continue end

local o=d.stateVersion
local p=UploadScriptSourceBatch(d.clientId,m)
if p then
local q=0
for r,s in m do
if s.kind=="source"and s.generation==d.generation then
if g:MarkMapped(s.debugId,false)then
q+=1
end
end
end
d.statusDirty=
d.stateVersion~=o+q
else
local q=false
for r=#m,1,-1 do
local s=m[r]
if s.generation~=d.generation then
continue
end

s.attempts=(s.attempts or 0)+1
if s.kind=="source"and s.attempts>=k then
q=g:MarkFailed(
s.debugId,
"Source upload failed after "..tostring(s.attempts).." attempts.",
false
)or q
else
EnqueueScriptSourceUpload(s)
end
end
if q then g:Publish()end
local r=m[1]and m[1].attempts or 1
task.wait(math.min(2^math.max(0,r-1),l))
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
end end function a.k():typeof(__modImpl())local b=a.cache.k if not b then b={c=__modImpl()}a.cache.k=b end return b.c end end do local function __modImpl()

return function(b)
local c=b.Request or request
local d=b.ScriptMappingPipeline
local e=b.HttpService
local f=b.BridgeURL
local g=b.StripDecompilerBanner
local h=b.base64_encode
local i=b.BuiltInDecompile
local j=b.GetScriptHash
local k=b.DecompilerAttemptState
local l=b.PreparedScript
local m=b.Concurrency
local n=256
local o=2
local p=3
local q=8
local r=65
local s={
providerId=nil,
expiresAt=0,
refreshToken=nil,
blockedBuiltinUntil=0,
}
local t={
startedAt=nil,
lastAt=nil,
samples=0,
lastReportAt=0,
revision=0,
}

local function RunWithTimeout(u,v)
local w=false
local x=false
local y

local z=task.spawn(function()
x,y=pcall(v)
w=true
end)

local A=os.clock()+u
while not w and os.clock()<A do
task.wait(0.05)
end

if not w then
pcall(task.cancel,z)
return false,"Timed out after "..tostring(u).."s."
end

if not x then
return false,y
end

return true,y
end

local function RememberScriptSourceForHash(u,v)
if type(u)~="string"or u==""then return false end
if type(v)~="string"or v==""then return false end

d.sourceCacheByHash[u]=v
d.sourceCacheCheckedByHash[u]=true
return true
end

local function ReadScriptHash(u)
if type(j)~="function"then return nil end

local v,w=RunWithTimeout(o,function()
return j(u)
end)

if not v or type(w)~="string"or w==""then
return nil
end

return w
end

local function GetScriptHashForInstance(u)
local v=u:GetDebugId()
if d.scriptHashByDebugId[v]~=nil then
return d.scriptHashByDebugId[v]or nil
end

local w=ReadScriptHash(u)
d.scriptHashByDebugId[v]=w or false
return w
end

local function FetchCachedScriptSourceBatch(u,v)
if#v==0 then return true end

local w,x=pcall(c,{
Url="http://"..f.."/script-source-cache",
Method="POST",
Headers={
["Content-Type"]="application/json",Accept=
"application/json",
},
Body=e:JSONEncode{
clientId=u,
hashes=v,
},
})

if not w or type(x)~="table"or x.StatusCode~=200 or type(x.Body)~="string"then
return false
end

local y,z=pcall(function()
return e:JSONDecode(x.Body)
end)
if not y or type(z)~="table"or type(z.sources)~="table"then
return false
end

for A,B in ipairs(z.sources)do
if type(B)=="table"then
RememberScriptSourceForHash(B.scriptHash,B.source)
end
end

return true
end

local function FetchCachedScriptSources(u,v)
if type(c)~="function"then return end
if type(u)~="string"or u==""then return end
if type(v)~="table"then return end

local w={}
local x={}
local function flush()
local y=FetchCachedScriptSourceBatch(u,w)
if y then
for z,A in w do
d.sourceCacheCheckedByHash[A]=true
end
end
table.clear(w)
end

for y,z in ipairs(v)do
if(
type(z)=="string"and
z~=""and
not d.sourceCacheByHash[z]and
not d.sourceCacheCheckedByHash[z]and
not x[z]
)then
x[z]=true
table.insert(w,z)
if#w>=n then
flush()
end
end
end

flush()
end

local function ReadScriptBytecode(u)
local v,w=RunWithTimeout(p,function()
return getscriptbytecode(u)
end)
if not v or w==nil then
return false,w or"Failed to read script bytecode."
end
return true,w
end

local function TryBuiltInDecompile(u)
if type(i)~="function"then
return nil,0,"Executor built-in decompile is unavailable.",false
end

local v=os.clock()
local w,x=RunWithTimeout(q,function()
return i(u)
end)
local y=math.floor((os.clock()-v)*1000)
if not w then
local z=tostring(x or"Built-in decompile failed.")
return nil,y,z,string.find(z,"Timed out",1,true)~=nil
end
if type(x)~="string"or x==""then
return nil,y,"Built-in decompile returned no source.",false
end

return g(x),y
end

local function IsActiveMappingContext(u,v)
return(
u==d.generation and
v~=nil and
v==d.clientId
)
end

local function RefreshDecompilerPlan(u,v,w)
v=v or d.generation
w=w or d.clientId
if not IsActiveMappingContext(v,w)then return nil end
local x=os.clock()
if not u and s.expiresAt>x then
return s.providerId
end
if s.refreshToken then
local y=x+2
repeat task.wait()until not s.refreshToken or os.clock()>=y
return s.providerId
end
if type(c)~="function"then return nil end

local y={}
s.refreshToken=y

local z,A=RunWithTimeout(5,function()
return c{
Url="http://"..f.."/decompile-plan?clientId="..e:UrlEncode(w),
Method="GET",
Headers={Accept=
"application/json",
},
}
end)
if s.refreshToken~=y then return nil end
s.refreshToken=nil
if not IsActiveMappingContext(v,w)then return nil end
if not z or type(A)~="table"or A.StatusCode~=200 or type(A.Body)~="string"then
s.providerId=nil
s.expiresAt=x+0.25
return nil
end

local B,C=pcall(function()
return e:JSONDecode(A.Body)
end)
if not B or type(C)~="table"then
s.providerId=nil
s.expiresAt=x+0.25
return nil
end

s.providerId=if type(C.providerId)=="string"then C.providerId else nil
local D=math.max(0.25,math.min((tonumber(C.ttlMs)or 1000)/1000,5))
s.expiresAt=os.clock()+D
return s.providerId
end

local function ShouldUseDirectBuiltIn(u,v,w)
if u~="builtin"then return false end
if s.blockedBuiltinUntil>os.clock()then return false end
return type(i)=="function"and RefreshDecompilerPlan(false,v,w)=="builtin"
end

local function PostBuiltInObservation(u,v,w)
if not IsActiveMappingContext(v,w)then return end
local x=d.session
if not x then return end
t.revision+=1
u.clientId=w
u.providerId="builtin"
u.observationSessionId=x.id
u.observationSessionStartedAt=x.startedAt
u.observationRevision=t.revision
u.beginObservationSession=true
task.defer(function()
if not IsActiveMappingContext(v,w)then return end
pcall(c,{
Url="http://"..f.."/decompiler-observations",
Method="POST",
Headers={
["Content-Type"]="application/json",Accept=
"application/json",
},
Body=e:JSONEncode(u),
})
end)
end

local function ReportBuiltInDecompileSuccess(u,v,w)
if not IsActiveMappingContext(v,w)then return end
local x=os.clock()
if t.lastAt==nil or x-t.lastAt>2 then
t.startedAt=x
t.samples=0
end

t.lastAt=x
t.startedAt=t.startedAt or x
t.samples+=1
if x-t.startedAt<0.25 then return end
if x-t.lastReportAt<0.5 then return end
t.lastReportAt=x

local y=math.max(0.001,x-t.startedAt)
PostBuiltInObservation({
latencyMs=u,
successCount=t.samples,
throughputPerSecond=t.samples/y,
throughputWindowMs=y*1000,
throughputSamples=t.samples,
},v,w)
end

local function ReportBuiltInDecompileFailure(u,v,w,x,y)
if not IsActiveMappingContext(x,y)then return end
s.providerId=nil
s.expiresAt=0
s.blockedBuiltinUntil=os.clock()+5
if w==true then m:Reduce()end
PostBuiltInObservation({
latencyMs=v,
errorMessage=tostring(u or"Built-in decompile failed."),
timedOut=w==true,
},x,y)
end

local function RequestServerDecompile(u,v,w,x)
if type(c)~="function"then
return nil,"request function is unavailable"
end

v=if type(v)=="table"then v else{}
local y={
clientId=x,
bytecode=h(u),
builtinAvailable=type(i)=="function",
}
if type(v.builtinSource)=="string"then
y.builtinSource=v.builtinSource
end
if type(v.builtinLatencyMs)=="number"then
y.builtinLatencyMs=v.builtinLatencyMs
end
if type(v.requestedProvider)=="string"then
y.requestedProvider=v.requestedProvider
end
if type(v.disabledProviders)=="table"then
y.disabledProviders=v.disabledProviders
end

local z,A=RunWithTimeout(r,function()
return c{
Url="http://"..f.."/decompile",
Method="POST",
Headers={
["Content-Type"]="application/json",Accept=
"application/json",
},
Body=e:JSONEncode(y),
}
end)
if not z then
return nil,tostring(A)
end

if type(A)~="table"or type(A.Body)~="string"then
return nil,"Decompile server returned no response body."
end

local B,C=pcall(function()
return e:JSONDecode(A.Body)
end)
if not B or type(C)~="table"then
return nil,"Decompile server returned invalid JSON."
end

local D
if type(C.attemptedProviders)=="table"and type(C.attemptedProviders[1])=="string"then
D=C.attemptedProviders[1]
end

if C.ok==true and type(C.source)=="string"and C.source~=""then
return g(C.source),nil,false,D
end
if C.needsBuiltin==true and C.providerId=="builtin"then
return nil,nil,true,D
end

if type(C.error)=="string"and C.error~=""then
return nil,C.error,false,D
end
if type(C.attempts)=="table"then
return nil,table.concat(C.attempts,"\n\n"),false,D
end

return nil,"Decompile server failed without a detailed error.",false,D
end

local function PrepareScriptForMapping(u,v,w,x,y)
w=w or d.generation
x=x or d.clientId
local z=u:GetDebugId()
local A=GetScriptHashForInstance(u)
if v and A then
FetchCachedScriptSources(x,{A})
end

local B=A and d.sourceCacheByHash[A]or nil
if B then
return{
debugId=z,
scriptHash=A,
source=B,
}
end

local C=RefreshDecompilerPlan(false,w,x)
local D=y or C
local E=y=="builtin"
if E or ShouldUseDirectBuiltIn(D,w,x)then
return{
debugId=z,
scriptHash=A,
retryProviderId=y,
useDirectBuiltin=true,
forceDirectBuiltinRetry=E,
}
end

local F,G=ReadScriptBytecode(u)
if not F then
return nil,G
end

return{
debugId=z,
scriptHash=A,
bytecode=G,
retryProviderId=y,
}
end

local function BuildServerOptions(u,v)
local w={}
if type(u.retryProviderId)=="string"then
w.requestedProvider=u.retryProviderId
end
if type(v)=="table"then
for x,y in v do
w[x]=y
end
end
return if next(w)==nil then nil else w
end

local function TakeRetryServerOptions(u,v)
local w=BuildServerOptions(u,v)
u.retryProviderId=nil
return w
end

local function DecompileScriptSource(u,v,w,x)
w=w or d.generation
x=x or d.clientId
local y
if not v then
v,y=PrepareScriptForMapping(u,true,w,x)
end
if not v then
return nil,y or"Failed to prepare script for decompile.",nil,nil
end

if type(v.source)=="string"and v.source~=""then
return v.source,nil,v.scriptHash,v
end
if v.useDirectBuiltin==true then
local z=v.forceDirectBuiltinRetry==true or
k.CanAttemptBuiltIn(
v,
s.blockedBuiltinUntil,
os.clock()
)
if z then
v.retryProviderId=nil
v.forceDirectBuiltinRetry=nil
v.initialProviderId=v.initialProviderId or"builtin"
k.MarkBuiltInAttempted(v)
local A,B,C,D=TryBuiltInDecompile(u)
if A then
ReportBuiltInDecompileSuccess(B,w,x)
if v.scriptHash then
RememberScriptSourceForHash(v.scriptHash,A)
end
return A,nil,v.scriptHash,v
end

k.DisableBuiltIn(v)
ReportBuiltInDecompileFailure(C,B,D,w,x)
end
local A,B=l.MaterializeServerFallback(v,function()
return ReadScriptBytecode(u)
end)
if not A then
return nil,B,v.scriptHash,v
end
end

if type(v.bytecode)~="string"then
return nil,"Prepared script is missing bytecode.",v.scriptHash,v
end

local z=TakeRetryServerOptions(
v,
if v.builtinDisabled==true then{disabledProviders={"builtin"}}else nil
)
local A,B,C,D=RequestServerDecompile(
v.bytecode,
z,
w,
x
)
if not v.initialProviderId and type(D)=="string"then
v.initialProviderId=D
end
if C then
local E=k.CanAttemptBuiltIn(
v,
s.blockedBuiltinUntil,
os.clock()
)
if E then
k.MarkBuiltInAttempted(v)
local F,G,H,I=TryBuiltInDecompile(u)
if F then
ReportBuiltInDecompileSuccess(G,w,x)
A,B=RequestServerDecompile(v.bytecode,BuildServerOptions(v,{
requestedProvider="builtin",
builtinSource=F,
builtinLatencyMs=G,
}),w,x)
else
k.DisableBuiltIn(v)
ReportBuiltInDecompileFailure(H,G,I,w,x)
A,B=RequestServerDecompile(v.bytecode,BuildServerOptions(v,{
disabledProviders={"builtin"},
}),w,x)
end
else
k.DisableBuiltIn(v)
A,B=RequestServerDecompile(v.bytecode,BuildServerOptions(v,{
disabledProviders={"builtin"},
}),w,x)
end
end
if not A then
return nil,B,v.scriptHash,v
end

if v.scriptHash then
RememberScriptSourceForHash(v.scriptHash,A)
end
return A,nil,v.scriptHash,v
end

local function ResetDecompilerClient()
s.providerId=nil
s.expiresAt=0
s.refreshToken=nil
s.blockedBuiltinUntil=0
t.startedAt=nil
t.lastAt=nil
t.samples=0
t.lastReportAt=0
t.revision=0
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
end end function a.l():typeof(__modImpl())local b=a.cache.l if not b then b={c=__modImpl()}a.cache.l=b end return b.c end end do local function __modImpl()

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

local function GetDataModelScripts()
local D,E=pcall(function()return game:QueryDescendants"LuaSourceContainer"end)
if D and type(E)=="table"then return E end
local F={}
for G,H in game:GetDescendants()do
if H:IsA"LuaSourceContainer"then table.insert(F,H)end
end
return F
end

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

for F,G in GetDataModelScripts()do
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
(g and D:IsDescendantOf(g))or
(h and D:IsDescendantOf(h))or
(i and D:IsDescendantOf(i))
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
GetDataModelScripts(),
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
end end function a.m():typeof(__modImpl())local b=a.cache.m if not b then b={c=__modImpl()}a.cache.m=b end return b.c end end do local function __modImpl()

return function(b,c)
local d=b.LogService
local e=b.Compatibility

c:BindToType("execute",function(f)
task.defer(function()
e.SetThreadIdentity(f.threadContext or 8)
local g,h=loadstring(f.source)
assert(g,h)
g()
end)
end)

c:BindToTypeRaw("get-console-output",function(f)
local g=math.max(1,math.min(tonumber(f.limit)or 20,200))
local h=f.logsOrder or"NewestFirst"
local i=f.filter
local j=typeof(i)=="string"and i~=""
local k=f.summaryOnly==true

local l=d:GetLogHistory()
local m={}
local n=0
local o={}

local function matchesFilter(p)
if not j then return true end
return string.find(p.message,i,1,true)~=nil
end

local p=500
local function formatLogMessage(q)
local r=tostring(q or"")
if#r>p then
r=string.sub(r,1,p)
.."…(+"..(#r-p).." chars omitted)"
end
return r
end

if h=="NewestFirst"then
for q=#l,1,-1 do
local r=l[q]
if not matchesFilter(r)then continue end

n+=1
local s=r.messageType and r.messageType.Name or"Unknown"
o[s]=(o[s]or 0)+1
if#m<g then
table.insert(m,r)
end
end
else
for q,r in l do
if not matchesFilter(r)then continue end

n+=1
local s=r.messageType and r.messageType.Name or"Unknown"
o[s]=(o[s]or 0)+1
if#m<g then
table.insert(m,r)
end
end
end

local q={}
if k then
table.insert(q,string.format("Matched %d logs.",n))
for r,s in o do
table.insert(q,string.format("%s: %d",r,s))
end
return table.concat(q,"\n")
end

table.insert(q,string.format("Displaying %d/%d logs:",#m,n))

for r,s in m do
table.insert(q,string.format(
"[%s t=%s] %s",
s.messageType.Name,tostring(s.timestamp),
formatLogMessage(s.message)
))
end

return table.concat(q,"\n")
end)

c:BindToType("get-data-by-code",function(f)
e.SetThreadIdentity(f.threadContext or 8)
local g,h=loadstring(f.source)
assert(g,h)
local i=table.pack(g())

return i
end)
end end function a.n():typeof(__modImpl())local b=a.cache.n if not b then b={c=__modImpl()}a.cache.n=b end return b.c end end do local function __modImpl()

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
b.Compatibility.SetThreadIdentity(8)
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
end end function a.o():typeof(__modImpl())local b=a.cache.o if not b then b={c=__modImpl()}a.cache.o=b end return b.c end end do local function __modImpl()

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
local g,h=pcall(function()return d:GetProductInfo(game.PlaceId)end)
if not g or type(h)~="table"then h={}end
local i=h.Creator or{}
local j="Unknown"
pcall(function()j=e.GetServerType:InvokeServer()end)

local k={
PlaceId=game.PlaceId,
GameId=game.GameId,
PlaceVersion=game.PlaceVersion,
PlaceName=h.Name,
Creator=i.Name,
CreatorType=i.CreatorType and tostring(i.CreatorType)or nil,
CreatorId=i.CreatorTargetId,
JobId=game.JobId,
ServerType=j,
Executor=b.Compatibility.Info,
}



if f.includeDescription==true then
k.PlaceDescription=h.Description
end

return k
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
end end function a.p():typeof(__modImpl())local b=a.cache.p if not b then b={c=__modImpl()}a.cache.p=b end return b.c end end do local function __modImpl()

return function(b,c)
local d=b.Environment
c:BindToType("ensure-remote-spy",function(e)
if d.Cobalt then
return{
status="already_loaded",
message="Cobalt remote spy is already running."
}
end


b.Compatibility.RequireRemoteSpySupport()
local f,g=pcall(function()
loadstring(game:HttpGet"https://github.com/notpoiu/cobalt/releases/latest/download/Cobalt.luau")()
end)

if not f then
error("Failed to load Cobalt: "..tostring(g))
end


local h=os.clock()
while not d.Cobalt and os.clock()-h<10 do
task.wait(0.1)
end

assert(d.Cobalt,"Cobalt loaded but failed to initialize within 10 seconds.")

return{
status="loaded",
message="Cobalt remote spy loaded successfully."
}
end)

c:BindToType("get-remote-spy-logs",function(e)
local f=d.Cobalt
assert(f and f.shared and f.shared.Logs,"Cobalt remote spy is not loaded. Call ensure-remote-spy first.")

local g=e.direction or"Both"
local h=e.remoteNameFilter or""
local i=math.max(1,math.min(tonumber(e.limit)or 10,100))
local j=math.max(0,math.min(tonumber(e.maxCallsPerRemote)or 2,20))
local k=e.summaryOnly==true
local l=h~=""

local function ProcessLogs(m,n)
local o={}

for p,q in m do
if typeof(p)~="Instance"then continue end
if#o>=i then break end

local r=""
local s=""
pcall(function()
r=p.Name
s=p.ClassName
end)


if l and not string.find(string.lower(r),string.lower(h),1,true)then
continue
end


local t={}
local u=#q.Calls
local v=math.max(1,u-j+1)

if not k then
for w=v,u do
local x=q.Calls[w]
if not x then continue end

table.insert(t,{
Index=w,
Arguments=x.Arguments,
Origin=x.Origin,
IsExecutor=x.IsExecutor or false,
IsActor=x.IsActor or false,
Line=x.Line,
})
end
end

table.insert(o,{
RemoteName=r,
RemoteClass=s,
Direction=n,
Method=q.Method,
TotalCalls=u,
Ignored=q.Ignored,
Blocked=q.Blocked,
RecentCalls=if k then nil else t,
})
end

return o
end

local m={}

if g=="Outgoing"or g=="Both"then
local n=ProcessLogs(f.shared.Logs.Outgoing,"Outgoing")
for o,p in n do
table.insert(m,p)
end
end

if g=="Incoming"or g=="Both"then
local n=ProcessLogs(f.shared.Logs.Incoming,"Incoming")
for o,p in n do
table.insert(m,p)
end
end


table.sort(m,function(n,o)
return n.TotalCalls>o.TotalCalls
end)


if#m>i then
local n={}
for o=1,i do
n[o]=m[o]
end
m=n
end

return{
count=#m,
results=m
}
end)
end end function a.q():typeof(__modImpl())local b=a.cache.q if not b then b={c=__modImpl()}a.cache.q=b end return b.c end end do local function __modImpl()

return function(b,c)
local d=b.Environment
c:BindToType("clear-remote-spy-logs",function(e)
local f=d.Cobalt
assert(f and f.shared and f.shared.ClearLogs,"Cobalt remote spy is not loaded. Call ensure-remote-spy first.")

f.shared.ClearLogs()

return{
status="cleared",
message="All remote spy logs have been cleared."
}
end)

c:BindToType("block-remote",function(e)
local f=d.Cobalt
assert(f and f.shared and f.shared.Logs,"Cobalt remote spy is not loaded. Call ensure-remote-spy first.")

local g=e.remoteName
local h=e.direction
local i=e.shouldBlock

local j=f.shared.Logs[h]
assert(j,"Invalid direction: "..tostring(h))

for k,l in j do
if typeof(k)~="Instance"then continue end

local m=""
pcall(function()m=k.Name end)

if m==g then
if i and not l.Blocked then
l:Block()
elseif not i and l.Blocked then
l:Block()
end

return{
status="success",
message=(i and"Blocked"or"Unblocked").." remote: "..g,
blocked=l.Blocked
}
end
end

error("Remote not found: "..g.." in "..h.." logs. Make sure the remote has been logged at least once.")
end)

c:BindToType("ignore-remote",function(e)
local f=d.Cobalt
assert(f and f.shared and f.shared.Logs,"Cobalt remote spy is not loaded. Call ensure-remote-spy first.")

local g=e.remoteName
local h=e.direction
local i=e.shouldIgnore

local j=f.shared.Logs[h]
assert(j,"Invalid direction: "..tostring(h))

for k,l in j do
if typeof(k)~="Instance"then continue end

local m=""
pcall(function()m=k.Name end)

if m==g then
if i and not l.Ignored then
l:Ignore()
elseif not i and l.Ignored then
l:Ignore()
end

return{
status="success",
message=(i and"Ignoring"or"Unignored").." remote: "..g,
ignored=l.Ignored
}
end
end

error("Remote not found: "..g.." in "..h.." logs. Make sure the remote has been logged at least once.")
end)




c:BindToType("remote-spy",function(e)
c.Callbacks["ensure-remote-spy"]{}

local f=e.operation
if f=="status"then
local g=d.Cobalt
local function CountLogs(h)
local i=0
if typeof(h)~="table"then return i end
for j in h do
i+=1
end
return i
end

return{
status="loaded",
outgoingRemotes=CountLogs(g.shared and g.shared.Logs and g.shared.Logs.Outgoing),
incomingRemotes=CountLogs(g.shared and g.shared.Logs and g.shared.Logs.Incoming),
}
elseif f=="list"then
return c.Callbacks["get-remote-spy-logs"]{
direction=e.direction,
remoteNameFilter=e.nameFilter,
limit=e.limit,
maxCallsPerRemote=e.maxCallsPerRemote,
summaryOnly=e.summaryOnly,
}
elseif f=="clear"then
return c.Callbacks["clear-remote-spy-logs"]{}
elseif f=="block"or f=="unblock"then
return c.Callbacks["block-remote"]{
remoteName=e.remoteName,
direction=e.direction,
shouldBlock=f=="block",
}
elseif f=="ignore"or f=="unignore"then
return c.Callbacks["ignore-remote"]{
remoteName=e.remoteName,
direction=e.direction,
shouldIgnore=f=="ignore",
}
end

error("Invalid remote-spy operation: "..tostring(f))
end)
end end function a.r():typeof(__modImpl())local b=a.cache.r if not b then b={c=__modImpl()}a.cache.r=b end return b.c end end do local function __modImpl()

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
assert(d or type(keypress)=="function","This executor cannot simulate text input; use useKeyPress=false to set Text directly.")
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

local i={"Activated","MouseButton1Down","MouseButton2Down","MouseButton1Click","MouseButton2Click"}

if g then assert(table.find(i,g),"Invalid action provided. Valid actions are: "..table.concat(i,", "))end
if typeof(firesignal)~="function"then
assert(d,"This executor supports neither firesignal nor VirtualInputManager; button clicking is unavailable.")
assert(g==nil or g=="Activated"or g=="MouseButton1Click"or g=="MouseButton2Click","Exact down-only signals require firesignal; select a click action for virtual mouse input.")
assert(h.Visible and h.AbsoluteSize.X>0 and h.AbsoluteSize.Y>0,"Virtual mouse clicking needs a visible button with a nonzero size.")
local j=h.AbsolutePosition+h.AbsoluteSize/2

local k=b.GuiService or game:GetService"GuiService"
local l=k:GetGuiInset()
local m,n=j.X+l.X,j.Y+l.Y
local o=g=="MouseButton2Click"and 1 or 0
d:SendMouseMoveEvent(m,n,game)
task.wait()
d:SendMouseButtonEvent(m,n,o,true,game,0)
task.wait(0.05)
local p,q=pcall(function()
d:SendMouseButtonEvent(m,n,o,false,game,0)
end)
assert(p,"Virtual mouse release failed: "..tostring(q))
return{status="success",method="virtual-input",message="Sent a mouse click; the button must be unobstructed and on screen."}
end

if g then
firesignal(h[g])
else
local j=0
for k,l in pairs(i)do
local m=pcall(function()firesignal(h[l])end)
if m then j+=1 end
end
assert(j>0,"The executor's firesignal function failed for every button signal.")
end

return{
status="success",
message="Successfully fired click signals on Button."
}
end)
end end function a.s():typeof(__modImpl())local b=a.cache.s if not b then b={c=__modImpl()}a.cache.s=b end return b.c end end do local function __modImpl()

return function(b)
local c=b.CreateBridge
local d=b.Environment
local e=b.WaitForBridgeClientId
local f=b.ScriptMappingPipeline
local g=b.StartUploadQueue
local h=b.PublishScriptMappingStatus
local i=b.ResetScriptMappingState
local j=b.StartScriptMapping
local k=b.StartFailedScriptResync
local l=b.ResumeDeferredScriptMappings

while true do
local m,n=pcall(c)

if not m then
task.wait(3)
continue
end

local o=e(n)
if o then
f.bridge=n
g()

if f.clientId~=o then
i(o)
end

if not d.DisableInitialScriptDecompMapping then
j(o)
k()
l()
h()
else
f.clientId=o
f.disabled=true
f.stateVersion+=1
h()
end
end

local p={a.n()
,a.o()
,a.p()
,a.q()
,a.r()
,a.s()
,
}
for q,r in p do
r(b,n)
end

n:WaitForDisconnect()

if f.bridge==n then
f.bridge=nil
end
task.wait(1)
end
end end function a.t():typeof(__modImpl())local b=a.cache.t if not b then b={c=__modImpl()}a.cache.t=b end return b.c end end end




local b=a.a().new()
local c=b.Environment
if c.MCP_Loaded==true then
return
end

assert(type(loadstring)=="function","This executor needs loadstring to run the MCP connector.")
assert(b.Info.available.request,"This executor needs an HTTP request function to connect to MCP.")

local d=c.BridgeURL or c.bridgeurl or...or"localhost:16384"
c.BridgeURL=d
c.bridgeurl=d


if not game:IsLoaded()then
game.Loaded:Wait()
end


local e=b.CloneReference
local function OptionalService(f)
local g,h=pcall(function()return e(game:GetService(f))end)
return g and h or nil
end

local f=OptionalService"RobloxReplicatedStorage"
local g,h=pcall(function()return e(Instance.new"VirtualInputManager")end)
if not g then h=nil end
local i:MarketplaceService=e(game:GetService"MarketplaceService")
local j=OptionalService"CoreGui"
local k=OptionalService"CorePackages"
local l=OptionalService"ScriptContext"
local m:HttpService=e(game:GetService"HttpService")
local n:LogService=e(game:GetService"LogService")
local o:Players=e(game:GetService"Players")



local p
do




local q='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'


p=base64encode or function(r)
return((r:gsub('.',function(s)
local t,u='',s:byte()
for v=8,1,-1 do t=t..(u%2^v-u%2^(v-1)>0 and'1'or'0')end
return t
end)..'0000'):gsub('%d%d%d?%d?%d?%d?',function(s)
if(#s<6)then return''end
local t=0
for u=1,6 do t=t+(s:sub(u,u)=='1'and 2^(6-u)or 0)end
return q:sub(t+1,t+1)
end)..({'','==','='})[#r%3+1])
end
end



local q=type(getscripthash)=="function"and getscripthash or nil
local r=type(decompile)=="function"and decompile or nil

local s=b.Request{
Url="https://raw.githubusercontent.com/chadhyatt/LuaEncode/refs/heads/master/src/LuaEncode.lua",
Method="GET",
}
assert(s.StatusCode==200 and type(s.Body)=="string","Unable to download the connector serializer.")
local t,u=loadstring(s.Body)
assert(t,u)
local v=t()




local w=8
local x=60
local y=500

local function SanitizeForOutput(z,A,B)
A=A or 0
local C=typeof(z)

if C=="Instance"then
local D,E=pcall(function()return z:GetFullName()end)
return D and E or tostring(z)
elseif C=="string"then
if#z>y then
return string.sub(z,1,y)
.."…(+"..(#z-y).." chars omitted)"
end
return z
elseif C=="number"or C=="boolean"or C=="nil"then
return z
elseif C~="table"then

return tostring(z)
end

if A>=w then
return"<table: max depth reached>"
end

B=B or{}
if B[z]then
return"<cyclic table>"
end
B[z]=true

local D={}
local E=0
local F=0
for G,H in pairs(z)do
if E>=x then
F+=1
continue
end
E+=1
local I=G
if typeof(G)~="string"and typeof(G)~="number"then
I=tostring(G)
end
D[I]=SanitizeForOutput(H,A+1,B)
end
if F>0 then
D.__omitted=F.." more entries omitted"
end

B[z]=nil
return D
end



local function StripDecompilerBanner(z)
if typeof(z)~="string"then return z end
return(string.gsub(z,"^%s*%-%-[^\n]*[Dd]ecompiled[^\n]*\n","",1))
end

local z=b.GetNilInstances


local A=b.ConnectWebSocket~=nil and c.DisableWebSocket~=true


local function GenerateSessionGuid()
local B,C=pcall(function()
return m:GenerateGUID(false)
end)
if B and type(C)=="string"and C~=""then
return C
end
return tostring(os.clock()).."-"..tostring(math.random(1,1000000000))
end

local function GetClientIdentityKey()
local B=o.LocalPlayer
return table.concat({
tostring(game.PlaceId or 0),
tostring(game.JobId or""),
tostring(B and B.UserId or 0),
},":")
end

local function GetStableClientSessionId()
local B=GetClientIdentityKey()
if type(c.MCP_ClientSessionId)~="string"or c.MCP_ClientIdentityKey~=B then
c.MCP_ClientSessionId=GenerateSessionGuid()
c.MCP_ClientIdentityKey=B
end
return c.MCP_ClientSessionId
end

local function GetRegistrationInfo()
local B=o.LocalPlayer
local C="Unknown"
pcall(function()
local D=i:GetProductInfo(game.PlaceId)
C=D.Name
end)
return{
type="register",
username=B and B.Name or"Unknown",
userId=B and B.UserId or 0,
placeId=game.PlaceId,
jobId=game.JobId,
placeName=C,
sessionId=GetStableClientSessionId(),
}
end


local B=a.b(){
Request=b.Request,
ConnectWebSocket=b.ConnectWebSocket,
HttpService=m,
BridgeURL=d,
WebSocketAvailable=A,
GetRegistrationInfo=GetRegistrationInfo,
SanitizeForOutput=SanitizeForOutput,
LuaEncode=v,
}
local C=B.CreateBridge


local D=a.c()
local E=a.d()
local F=a.e()
local G=a.f()
local H=a.g()
local I=E.new()
local J=math.max(
1,
math.min(math.floor(tonumber(c.MCP_ScriptMappingWorkers)or 24),64)
)
local K=a.h().new(
I,
J
)
local L=math.max(
5,
math.min(tonumber(c.MCP_FailedScriptResyncInterval)or 30,600)
)
local M=a.i().new(I,{
IntervalSeconds=L,
MaxDelaySeconds=math.max(L,300),
BatchSize=math.max(
1,
math.min(math.floor(tonumber(c.MCP_FailedScriptResyncBatchSize)or 8),32)
),
})
local N=a.j().new(
I,
M
)
local O=a.k(){
Request=b.Request,
ScriptMappingPipeline=I,
HttpService=m,
BridgeURL=d,
JobStatus=N,
}
local P=a.l(){
Request=b.Request,
ScriptMappingPipeline=I,
HttpService=m,
BridgeURL=d,
StripDecompilerBanner=StripDecompilerBanner,
base64_encode=p,
BuiltInDecompile=r,
GetScriptHash=q,
DecompilerAttemptState=G,
PreparedScript=H,
Concurrency=K,
}
local Q=a.m(){
ScriptMappingPipeline=I,
WorkerPool=D,
UploadSession=F,
GenerateSessionGuid=GenerateSessionGuid,
CoreGui=j,
CorePackages=k,
ScriptContext=l,
getnilinstances=z,
WorkerCount=J,
Concurrency=K,
JobStatus=N,
FailedResync=M,
UploadClient=O,
DecompilerClient=P,
}
local R=O.StartUploadQueue
local function PublishScriptMappingStatus()
N:Publish()
end
local S=Q.StartScriptMapping
local T=Q.StartFailedScriptResync
local U=Q.ResetScriptMappingState
local V=Q.ResumeDeferredScriptMappings
local W=Q.GetScriptByDebugId
local X=Q.QueueMappedScriptSource
local Y=Q.DecompileScriptSource

local function WaitForBridgeClientId(Z)
local aa=os.clock()+5
repeat
if Z.ClientId then
return Z.ClientId
end
if not Z.Connected then
return nil
end
task.wait(0.05)
until os.clock()>aa

return nil
end

c.MCP_Loaded=true a.t()
{
Compatibility=b,
Environment=c,
CreateBridge=C,
WaitForBridgeClientId=WaitForBridgeClientId,
ScriptMappingPipeline=I,
StartUploadQueue=R,
PublishScriptMappingStatus=PublishScriptMappingStatus,
ResetScriptMappingState=U,
StartScriptMapping=S,
StartFailedScriptResync=T,
ResumeDeferredScriptMappings=V,
GetScriptByDebugId=W,
DecompileScriptSource=Y,
QueueMappedScriptSource=X,
LogService=n,
MarketplaceService=i,
RobloxReplicatedStorage=f,
VirtualInputManager=h,
LuaEncode=v,
}