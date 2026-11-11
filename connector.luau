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

local m={Environment=d,Info=k,ConnectWebSocket=j,Lookup=lookup}

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


function m.HttpGet(n)
local o,p=pcall(function()
return game:HttpGet(n)
end)
if o and type(p)=="string"then
return p
end
local q=m.Request{Url=n,Method="GET"}
assert(q.StatusCode==200 and type(q.Body)=="string",
"HTTP GET "..n.." failed with status "..tostring(q.StatusCode))
return q.Body
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

function k.TrackThread(l,m)
local n
n=task.spawn(function()
m()
if n and l.CommandThreads then
l.CommandThreads[n]=nil
end
end)

if l.CommandThreads and coroutine.status(n)~="dead"then
l.CommandThreads[n]=true
end
return n
end



function k.MarkReplaced(l,m)
l.Replaced=true
l.DisconnectReason="replaced: "..tostring(m and m.reason or"another connector took over")
l.Connected=false
end

function k.Destroy(l)
l.Connected=false
local m=coroutine.running()
for n,o in{"AliveThread","PollThread","ProbeThread"}do
local p=l[o]
l[o]=nil
if p and p~=m then pcall(task.cancel,p)end
end
if l.CommandThreads then
local n=l.CommandThreads
l.CommandThreads={}
for o in n do
if o~=m then pcall(task.cancel,o)end
end
end
for n,o in{"MessageConnection","CloseConnection"}do
local p=l[o]
l[o]=nil
if p then pcall(function()p:Disconnect()end)end
end
if l.WebSocket then
local n=l.WebSocket
l.WebSocket=nil
pcall(function()n:Close()end)
end
if l.Callbacks then table.clear(l.Callbacks)end
if l.RawCallbacks then table.clear(l.RawCallbacks)end
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
else
l.LastProbeError="request failed: "..tostring(o)
end
end)
l.ProbeThread=n

local o=os.clock()
repeat task.wait(0.05)until m~=nil or os.clock()-o>5
l.ProbeThread=nil

if m==nil then
task.cancel(n)
l.LastProbeError=l.LastProbeError or("no response from http://"..f.." within 5 seconds")
return false
end


if m.StatusCode==426 or m.StatusCode==200 then
l.LastProbeError=nil
return true
end

l.LastProbeError="unexpected HTTP status "..tostring(m.StatusCode).." from http://"..f.." (is this the MCP server?)"
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
error("Failed to reach the MCP server at "..f.." after "..p.." attempts: "..tostring(m.LastProbeError or"unknown error"))
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

m.AliveThread=task.spawn(function()
local u=0
while m.Connected do
task.wait(1)
if not m.Connected then
break
end

if m:IsAlive()then
u=0
continue
end

u+=1
if u<3 then
continue
end

m.DisconnectReason="3 heartbeat checks failed in a row: "..tostring(m.LastProbeError or"unknown error")
m.Connected=false
break
end

local v=m.WebSocket
if v then
pcall(function()
v:Close()
end)
end
end)



m.MessageConnection=m.WebSocket.OnMessage:Connect(function(u)
local v=e:JSONDecode(u)


if v.type=="registered"then
m.ClientId=v.clientId
return
end
if v.type=="replaced"then
m:MarkReplaced(v)
return
end

local w=m:HandleMessage(v)
local x=m.WebSocket
if w and x then
x:Send(e:JSONEncode(w))
end
end)


m.CloseConnection=m.WebSocket.OnClose:Connect(function()
m.DisconnectReason=m.DisconnectReason or"the WebSocket was closed"
m.Connected=false
end)


local u,v=pcall(function()
m.WebSocket:Send(e:JSONEncode(h()))
end)
if not u then
m:Destroy()
error(v)
end

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
error("Failed to reach the MCP server at "..f.." after "..q.." attempts: "..tostring(n.LastProbeError or"unknown error"))
end
task.wait(o)
o=math.min(o*1.5,p)
end

n.Connected=true
n.Callbacks={}
n.PollInterval=0.1
n.ClientId=nil
n.CommandThreads={}


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
local t=false
local u,v=pcall(function()
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
n.DisconnectReason="3 polls in a row returned HTTP "..tostring(v.StatusCode)
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
if z.type=="replaced"then
n:MarkReplaced(z)
break
end
t=true
n:TrackThread(function()
local A=n:HandleMessage(z)
if A==nil or not n.Connected then return end


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
n.DisconnectReason="3 polls in a row failed: "..tostring(v)
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











local b={}
b.__index=b

local c={
RemoteEvent="FireServer",
UnreliableRemoteEvent="FireServer",
RemoteFunction="InvokeServer",
BindableEvent="Fire",
BindableFunction="Invoke",
}
local d={BindableEvent=true,BindableFunction=true}
local e={RemoteEvent=true,UnreliableRemoteEvent=true}
local f={FireServer=true,InvokeServer=true,Fire=true,Invoke=true}

local g=50
local h=1000

local function identity(i)
return i
end

local function newDirectionTable()
return{Outgoing={},Incoming={}}
end

function b.new(i)
local j=setmetatable({},b)
j.Lookup=i.Lookup
j.Game=i.Game
j.InstanceNew=i.InstanceNew
j.TypeOf=i.TypeOf or typeof
j.Clock=i.Clock or os.clock
j.Encode=i.LuaEncode

j.Enabled=true
j.IncludeBindables=false
j.IncludeExecutorCalls=false

j.Logs=newDirectionTable()
j.RemoteCounts={Outgoing=0,Incoming=0}
j.BlockRules=newDirectionTable()
j.IgnoreRules=newDirectionTable()

j.OutgoingMode="unavailable"
j.FunctionHooks=0
j.IncomingMode="unavailable"
j.Watched=setmetatable({},{__mode="k"})
j.WatchedCount=0
j.InNamecall=setmetatable({},{__mode="k"})
j.Notes={}
return j
end

function b.SafeIndex(i,j,k)
local l,m=pcall(function()
return j[k]
end)
if l then return m end
return nil
end

function b.IsTarget(i,j,k)
if i.TypeOf(j)~="Instance"then return false end
local l=i:SafeIndex(j,"ClassName")
if c[l]~=k then return false end
if d[l]and not i.IncludeBindables then return false end
return true
end


function b.Record(i,j,k,l,m,n)
if not i.Enabled then return false end
local o=i:SafeIndex(j,"Name")or"?"
local p=i.BlockRules[k][o]==true
if i.IgnoreRules[k][o]then return p end

local q=i.Logs[k]
local r=q[j]
if not r then
if i.RemoteCounts[k]>=h then return p end
r={
Instance=j,
Name=o,
ClassName=i:SafeIndex(j,"ClassName")or"?",
Direction=k,
Method=l,
Calls={},
Head=0,
TotalCalls=0,
FirstSeen=i.Clock(),
}
q[j]=r
i.RemoteCounts[k]+=1
end

r.Name=o
r.TotalCalls+=1
r.LastSeen=i.Clock()
r.Head=r.Head%g+1
r.Calls[r.Head]={
Number=r.TotalCalls,
Arguments=m,
Time=r.LastSeen,
Script=n and n.Script or nil,
IsExecutor=n and n.IsExecutor or false,
Blocked=p,
}
return p
end


function b.RecentCalls(i,j,k)
local l=math.min(j.TotalCalls,g)
k=math.min(k,l)
local m={}
for n=k-1,0,-1 do
local o=(j.Head-n-1)%g+1
table.insert(m,j.Calls[o])
end
return m
end

function b.CallMeta(i)
local j=i.Lookup"checkcaller"
local k=i.Lookup"getcallingscript"
local l=false
if type(j)=="function"then
local m,n=pcall(j)
l=m and n==true
end
local m
if type(k)=="function"then
local n,o=pcall(k)
if n and i.TypeOf(o)=="Instance"then m=o end
end
return{IsExecutor=l,Script=m}
end


function b.InterceptOutgoing(i,j,k,...)
if not i.Enabled or not i:IsTarget(j,k)then return false end
local l=i:CallMeta()

if l.IsExecutor and not i.IncludeExecutorCalls then return false end
return i:Record(j,"Outgoing",k,table.pack(...),l)
end

function b.InstallNamecallHook(i)
local j=i.Lookup"getnamecallmethod"
if type(j)~="function"then
table.insert(i.Notes,"getnamecallmethod is missing, so remote:FireServer() calls cannot be intercepted through __namecall.")
return false
end
local k=i.Lookup"newcclosure"
if type(k)~="function"then k=identity end
local l=i
local m

local function handler(n,...)
local o=j()
if not f[o]or not l.Enabled then
return m(n,...)
end
if l:InterceptOutgoing(n,o,...)then
return nil
end

local p=coroutine.running()
l.InNamecall[p]=true
local q=table.pack(m(n,...))
l.InNamecall[p]=nil
return table.unpack(q,1,q.n)
end

local n=i.Lookup"hookmetamethod"
if type(n)=="function"then
local o,p=pcall(n,i.Game,"__namecall",k(handler))
if o and type(p)=="function"then
m=p
i.OutgoingMode="namecall-hook"
return true
end
table.insert(i.Notes,"hookmetamethod failed: "..tostring(p))
end

local o=i.Lookup"getrawmetatable"
if type(o)=="function"then
local p,q=pcall(function()
local p=o(i.Game)
local q=i.Lookup"setreadonly"
local r=i.Lookup"make_writeable"
m=p.__namecall
assert(type(m)=="function","game has no __namecall")
if type(q)=="function"then
q(p,false)
elseif type(r)=="function"then
r(p)
end
p.__namecall=k(handler)
if type(q)=="function"then pcall(q,p,true)end
end)
if p then
i.OutgoingMode="metatable"
return true
end
table.insert(i.Notes,"raw metatable namecall swap failed: "..tostring(q))
end
return false
end

function b.InstallFunctionHooks(i)
local j=i.Lookup"hookfunction"or i.Lookup"replaceclosure"or i.Lookup"detour_function"
if type(j)~="function"then
table.insert(i.Notes,"hookfunction is missing, so direct remote.FireServer(remote) calls are not intercepted.")
return false
end
local k=i.Lookup"newcclosure"
if type(k)~="function"then k=identity end
local l=i
local m={}

for n,o in c do
local p,q=pcall(function()
return i.InstanceNew(n)[o]
end)
if not p or type(q)~="function"or m[q]then continue end
m[q]=true

local r
local s,t=pcall(j,q,k(function(s,...)
if l.Enabled and not l.InNamecall[coroutine.running()]then
if l:InterceptOutgoing(s,o,...)then
return nil
end
end
return r(s,...)
end))
if s and type(t)=="function"then
r=t
i.FunctionHooks+=1
else
table.insert(i.Notes,"hookfunction failed on "..n.."."..o..": "..tostring(t))
end
end
return i.FunctionHooks>0
end

function b.ApplyIncomingBlock(i,j)
local k=i.Watched[j]
local l=i.Lookup"getconnections"
if not k or type(l)~="function"then return false end
local m=i:SafeIndex(j,"Name")or"?"
local n=i.BlockRules.Incoming[m]==true
k.Disabled=k.Disabled or{}
local o=pcall(function()
if n then
for o,p in l(j.OnClientEvent)do
if p.Function==k.Handler then continue end
p:Disable()
table.insert(k.Disabled,p)
end
else


for o,p in k.Disabled do
pcall(function()p:Enable()end)
end
table.clear(k.Disabled)
end
end)
return o
end

function b.Watch(i,j)
if i.Watched[j]then return end
local k=i:SafeIndex(j,"ClassName")
if not e[k]then return end

local l=i
local m={}
m.Handler=function(...)
if l:Record(j,"Incoming","OnClientEvent",table.pack(...),nil)then

l:ApplyIncomingBlock(j)
end
end
local n,o=pcall(function()
return j.OnClientEvent:Connect(m.Handler)
end)
if not n then return end
m.Connection=o
i.Watched[j]=m
i.WatchedCount+=1
if i.BlockRules.Incoming[i:SafeIndex(j,"Name")or"?"]then
i:ApplyIncomingBlock(j)
end
end

function b.InstallIncoming(i)
local j=i
local k=pcall(function()
i.DescendantConnection=i.Game.DescendantAdded:Connect(function(k)
j:Watch(k)
end)
end)
local l=pcall(function()
for l,m in i.Game:GetDescendants()do
j:Watch(m)
end
end)
local m=i.Lookup"getnilinstances"
if type(m)=="function"then
pcall(function()
for n,o in m()do
j:Watch(o)
end
end)
end
if k or l then
i.IncomingMode="connections"
return true
end
table.insert(i.Notes,"Could not scan the game for RemoteEvents.")
return false
end

function b.Start(i)
if i.Started then return i end
i.Started=true
local j=i:InstallNamecallHook()
local k=i:InstallFunctionHooks()
if not j and k then
i.OutgoingMode="function-hook"
end
i:InstallIncoming()
return i
end


function b.SetRule(i,j,k,l,m)
local n=(j=="block"and i.BlockRules or i.IgnoreRules)[k]
assert(n,"Invalid direction: "..tostring(k).." (use Incoming or Outgoing)")
assert(type(l)=="string"and l~="","remoteName is required")
n[l]=m or nil

local o=0
for p,q in i.Logs[k]do
if q.Name==l then o+=1 end
end
local p=true
if j=="block"and k=="Incoming"then
for q in i.Watched do
if i:SafeIndex(q,"Name")==l then
p=i:ApplyIncomingBlock(q)and p
end
end
end
return o,p
end

function b.Clear(i)
i.Logs=newDirectionTable()
i.RemoteCounts={Outgoing=0,Incoming=0}
end

local function formatIndex(i)
if string.match(i,"^[%a_][%w_]*$")then
return"."..i
end
return"["..string.format("%q",i).."]"
end

function b.PathOf(i,j)
local k={}
local l=j
for m=1,200 do
local n=i:SafeIndex(l,"Parent")
if n==nil then
return nil
end
if n==i.Game then
local o=i:SafeIndex(l,"ClassName")or"Workspace"
table.insert(k,1,string.format("game:GetService(%q)",o))
return table.concat(k)
end
table.insert(k,1,formatIndex(i:SafeIndex(l,"Name")or"?"))
l=n
end
return nil
end

function b.ReplayFor(i,j,k)
local l=i:PathOf(j.Instance)
if not l then
return"-- "..j.Name.." is parented to nil; find it with getnilinstances() first."
end
local m=k.Arguments
local n={}
for o=1,m.n or#m do
n[o]=m[o]
end
local o,p=pcall(i.Encode,n,{Prettify=false})
if not o then
p="{} -- arguments could not be serialized: "..tostring(p)
end
local q=m.n or#m
if j.Direction=="Incoming"then
return string.format(
"local args = %s\nfiresignal(%s.OnClientEvent, table.unpack(args, 1, %d))",
p,l,q
)
end
return string.format(
"local args = %s\n%s:%s(table.unpack(args, 1, %d))",
p,l,j.Method,q
)
end

function b.Status(i)
local j=i.Lookup"getconnections"
local k,l={},{}
for m in i.BlockRules.Outgoing do table.insert(k,"block "..m)end
for m in i.IgnoreRules.Outgoing do table.insert(k,"ignore "..m)end
for m in i.BlockRules.Incoming do table.insert(l,"block "..m)end
for m in i.IgnoreRules.Incoming do table.insert(l,"ignore "..m)end
return{
status="running",
enabled=i.Enabled,
outgoing=i.OutgoingMode,
outgoingFunctionHooks=i.FunctionHooks,
outgoingBlocking=i.OutgoingMode~="unavailable",
incoming=i.IncomingMode,
incomingBlocking=type(j)=="function",
remoteEventsWatched=i.WatchedCount,
outgoingRemotes=i.RemoteCounts.Outgoing,
incomingRemotes=i.RemoteCounts.Incoming,
includeBindables=i.IncludeBindables,
includeExecutorCalls=i.IncludeExecutorCalls,
outgoingRules=k,
incomingRules=l,
notes=i.Notes,
}
end

function b.List(i,j)
local k=j.direction or"Both"
local l=string.lower(j.nameFilter or"")
local m=math.clamp(math.floor(tonumber(j.limit)or 10),1,100)
local n=math.clamp(math.floor(tonumber(j.maxCallsPerRemote)or 2),0,20)
local o=j.summaryOnly==true

local p={}
for q,r in{"Outgoing","Incoming"}do
if k~="Both"and k~=r then continue end
for s,t in i.Logs[r]do
if l~=""and not string.find(string.lower(t.Name),l,1,true)then continue end
table.insert(p,t)
end
end
table.sort(p,function(q,r)
if q.TotalCalls~=r.TotalCalls then return q.TotalCalls>r.TotalCalls end
return q.Name<r.Name
end)

local q={}
for r=1,math.min(m,#p)do
local s=p[r]
local t={
RemoteName=s.Name,
RemoteClass=s.ClassName,
Path=i:PathOf(s.Instance),
Direction=s.Direction,
Method=s.Method,
TotalCalls=s.TotalCalls,
Blocked=i.BlockRules[s.Direction][s.Name]==true,
Ignored=i.IgnoreRules[s.Direction][s.Name]==true,
}
if not o and n>0 then
local u={}
for v,w in i:RecentCalls(s,n)do
local x={}
for y=1,w.Arguments.n or#w.Arguments do
x[y]=w.Arguments[y]
end
table.insert(u,{
Number=w.Number,
Arguments=x,
ArgumentCount=w.Arguments.n,
Script=w.Script and(i:PathOf(w.Script)or i:SafeIndex(w.Script,"Name"))or nil,
IsExecutor=w.IsExecutor,
Blocked=w.Blocked,
SecondsAgo=math.floor((i.Clock()-w.Time)*10)/10,
Replay=i:ReplayFor(s,w),
})
end
t.RecentCalls=u
end
table.insert(q,t)
end
return{count=#q,totalMatching=#p,results=q}
end



function b.Get(i)
local j=i.Environment
local k=j.MCP_RemoteSpy
if type(k)=="table"and type(k.List)=="function"then


if getmetatable(k)~=b then
setmetatable(k,b)
end
return k
end
local l=b.new{
Lookup=i.Compatibility.Lookup,
Game=game,
InstanceNew=Instance.new,
LuaEncode=i.LuaEncode,
}
l:Start()
j.MCP_RemoteSpy=l
return l
end

return b end function a.q():typeof(__modImpl())local b=a.cache.q if not b then b={c=__modImpl()}a.cache.q=b end return b.c end end do local function __modImpl()

local b=a.q()

return function(c,d)
d:BindToType("ensure-remote-spy",function()
local e=type(c.Environment.MCP_RemoteSpy)=="table"
local f=b.Get(c)
local g=f:Status()
g.status=e and"already_running"or"started"
return g
end)

d:BindToType("get-remote-spy-logs",function(e)
return b.Get(c):List{
direction=e.direction,
nameFilter=e.remoteNameFilter or e.nameFilter,
limit=e.limit,
maxCallsPerRemote=e.maxCallsPerRemote,
summaryOnly=e.summaryOnly,
}
end)
end end function a.r():typeof(__modImpl())local b=a.cache.r if not b then b={c=__modImpl()}a.cache.r=b end return b.c end end do local function __modImpl()

local b=a.q()

return function(c,d)
local function SetRule(e,f,g)
local h=b.Get(c)
local i,j=h:SetRule(e,f.direction,f.remoteName,g)
local k=if e=="block"
then(g and"Blocked"or"Unblocked")
else(g and"Ignoring"or"Unignored")
local l={
status="success",
message=string.format("%s %s remote %q. Matches %d logged remote(s); the rule also applies to remotes that have not fired yet.",
k,f.direction,f.remoteName,i),
matchedRemotes=i,
}
if e=="block"and f.direction=="Outgoing"and h.OutgoingMode=="unavailable"then
l.warning="Outgoing calls cannot be intercepted on this executor, so this block has no effect."
elseif e=="block"and f.direction=="Incoming"and not j then
l.warning="Blocking incoming events needs getconnections, which this executor lacks. Events are still logged."
end
return l
end

d:BindToType("clear-remote-spy-logs",function()
b.Get(c):Clear()
return{status="cleared",message="All remote spy logs have been cleared. Block and ignore rules are kept."}
end)

d:BindToType("block-remote",function(e)
return SetRule("block",e,e.shouldBlock~=false)
end)

d:BindToType("ignore-remote",function(e)
return SetRule("ignore",e,e.shouldIgnore~=false)
end)

d:BindToType("remote-spy",function(e)
local f=b.Get(c)
local g=e.operation

if g=="status"then
return f:Status()
elseif g=="list"then
return f:List(e)
elseif g=="clear"then
f:Clear()
return{status="cleared",message="All remote spy logs have been cleared. Block and ignore rules are kept."}
elseif g=="block"or g=="unblock"then
return SetRule("block",e,g=="block")
elseif g=="ignore"or g=="unignore"then
return SetRule("ignore",e,g=="ignore")
elseif g=="configure"then
if e.enabled~=nil then f.Enabled=e.enabled==true end
if e.includeBindables~=nil then f.IncludeBindables=e.includeBindables==true end
if e.includeExecutorCalls~=nil then f.IncludeExecutorCalls=e.includeExecutorCalls==true end
return f:Status()
end

error("Invalid remote-spy operation: "..tostring(g))
end)
end end function a.s():typeof(__modImpl())local b=a.cache.s if not b then b={c=__modImpl()}a.cache.s=b end return b.c end end do local function __modImpl()

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
end end function a.t():typeof(__modImpl())local b=a.cache.t if not b then b={c=__modImpl()}a.cache.t=b end return b.c end end do local function __modImpl()

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
local m=b.IsCurrentConnector or function()return true end



local n
local function Report(o,p)
if p==n then return end
n=p
local q=if o=="warn"then warn else print
q("[roblox-mcp] "..p)
end

Report("print","connector loaded, connecting to "..tostring(d.BridgeURL))

while m()do
local o,p=pcall(c)

if not m()then
if o then p:Destroy()end
break
end

if not o then
Report("warn","cannot connect: "..tostring(p).." (retrying)")
task.wait(3)
continue
end

local q=e(p)
if q then
Report("print","connected to "..tostring(d.BridgeURL)
.." via "..(if p.WebSocket then"WebSocket"else"HTTP polling")
.." as "..tostring(q))
f.bridge=p
g()

if f.clientId~=q then
i(q)
end

if not d.DisableInitialScriptDecompMapping then
j(q)
k()
l()
h()
else
f.clientId=q
f.disabled=true
f.stateVersion+=1
h()
end
end

local r={a.n()
,a.o()
,a.p()
,a.r()
,a.s()
,a.t()
,
}
for s,t in r do
t(b,p)
end

if not q then
Report("warn","connected, but the server never confirmed registration")
end


while p.Connected and m()do
task.wait(0.25)
end
local s=p.Replaced==true
if s then
Report("warn","another connector took over this session, stopping this one")
elseif m()then
Report("warn","disconnected: "..tostring(p.DisconnectReason or"unknown reason")..", reconnecting")
end
p:Destroy()

if f.bridge==p then
f.bridge=nil
end
if s then
return
end
task.wait(1)
end

print"[roblox-mcp] previous connector stopped, a newer one took over"
end end function a.u():typeof(__modImpl())local b=a.cache.u if not b then b={c=__modImpl()}a.cache.u=b end return b.c end end end




local b=a.a().new()
local c=b.Environment



local d=(tonumber(c.MCP_Generation)or 0)+1
c.MCP_Generation=d
if c.MCP_Loaded==true then
print"[roblox-mcp] replacing the connector already running in this session"
end
local function IsCurrentConnector()
return c.MCP_Generation==d
end

assert(type(loadstring)=="function","This executor needs loadstring to run the MCP connector.")
assert(b.Info.available.request,"This executor needs an HTTP request function to connect to MCP.")




local e=...
if type(e)=="string"then
e={BridgeURL=e}
end
do
local f={}
if type(e)=="table"then table.insert(f,e)end
table.insert(f,c)
for g,h in{
function()return _G end,
function()return shared end,
function()return getfenv(0)end,
}do
local i,j=pcall(h)
if i and type(j)=="table"then table.insert(f,j)end
end
for g,h in{
"BridgeURL","bridgeurl","DisableWebSocket","DisableInitialScriptDecompMapping",
"MCP_ScriptMappingWorkers","MCP_FailedScriptResyncInterval","MCP_FailedScriptResyncBatchSize",
}do
for i,j in f do
local k,l=pcall(function()return j[h]end)
if k and l~=nil then
c[h]=l
break
end
end
end
end

local f=c.BridgeURL or c.bridgeurl or"localhost:16384"
c.BridgeURL=f
c.bridgeurl=f


if not game:IsLoaded()then
game.Loaded:Wait()
end


local g=b.CloneReference
local function OptionalService(h)
local i,j=pcall(function()return g(game:GetService(h))end)
return i and j or nil
end

local h=OptionalService"RobloxReplicatedStorage"
local i,j=pcall(function()return g(Instance.new"VirtualInputManager")end)
if not i then j=nil end
local k:MarketplaceService=g(game:GetService"MarketplaceService")
local l=OptionalService"CoreGui"
local m=OptionalService"CorePackages"
local n=OptionalService"ScriptContext"
local o:HttpService=g(game:GetService"HttpService")
local p:LogService=g(game:GetService"LogService")
local q:Players=g(game:GetService"Players")



local r
do




local s='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'


r=base64encode or function(t)
return((t:gsub('.',function(u)
local v,w='',u:byte()
for x=8,1,-1 do v=v..(w%2^x-w%2^(x-1)>0 and'1'or'0')end
return v
end)..'0000'):gsub('%d%d%d?%d?%d?%d?',function(u)
if(#u<6)then return''end
local v=0
for w=1,6 do v=v+(u:sub(w,w)=='1'and 2^(6-w)or 0)end
return s:sub(v+1,v+1)
end)..({'','==','='})[#t%3+1])
end
end



local s=type(getscripthash)=="function"and getscripthash or nil
local t=type(decompile)=="function"and decompile or nil

local u=b.Request{
Url="https://raw.githubusercontent.com/chadhyatt/LuaEncode/refs/heads/master/src/LuaEncode.lua",
Method="GET",
}
assert(u.StatusCode==200 and type(u.Body)=="string","Unable to download the connector serializer.")
local v,w=loadstring(u.Body)
assert(v,w)
local x=v()




local y=8
local z=60
local A=500

local function SanitizeForOutput(B,C,D)
C=C or 0
local E=typeof(B)

if E=="Instance"then
local F,G=pcall(function()return B:GetFullName()end)
return F and G or tostring(B)
elseif E=="string"then
if#B>A then
return string.sub(B,1,A)
.."…(+"..(#B-A).." chars omitted)"
end
return B
elseif E=="number"or E=="boolean"or E=="nil"then
return B
elseif E~="table"then

return tostring(B)
end

if C>=y then
return"<table: max depth reached>"
end

D=D or{}
if D[B]then
return"<cyclic table>"
end
D[B]=true

local F={}
local G=0
local H=0
for I,J in pairs(B)do
if G>=z then
H+=1
continue
end
G+=1
local K=I
if typeof(I)~="string"and typeof(I)~="number"then
K=tostring(I)
end
F[K]=SanitizeForOutput(J,C+1,D)
end
if H>0 then
F.__omitted=H.." more entries omitted"
end

D[B]=nil
return F
end



local function StripDecompilerBanner(B)
if typeof(B)~="string"then return B end
return(string.gsub(B,"^%s*%-%-[^\n]*[Dd]ecompiled[^\n]*\n","",1))
end

local B=b.GetNilInstances


local C=b.ConnectWebSocket~=nil and c.DisableWebSocket~=true


local function GenerateSessionGuid()
local D,E=pcall(function()
return o:GenerateGUID(false)
end)
if D and type(E)=="string"and E~=""then
return E
end
return tostring(os.clock()).."-"..tostring(math.random(1,1000000000))
end

local function GetClientIdentityKey()
local D=q.LocalPlayer
return table.concat({
tostring(game.PlaceId or 0),
tostring(game.JobId or""),
tostring(D and D.UserId or 0),
},":")
end

local function GetStableClientSessionId()
local D=GetClientIdentityKey()
if type(c.MCP_ClientSessionId)~="string"or c.MCP_ClientIdentityKey~=D then
c.MCP_ClientSessionId=GenerateSessionGuid()
c.MCP_ClientIdentityKey=D
end
return c.MCP_ClientSessionId
end

local function GetRegistrationInfo()
local D=q.LocalPlayer
local E="Unknown"
pcall(function()
local F=k:GetProductInfo(game.PlaceId)
E=F.Name
end)
return{
type="register",
username=D and D.Name or"Unknown",
userId=D and D.UserId or 0,
placeId=game.PlaceId,
jobId=game.JobId,
placeName=E,
sessionId=GetStableClientSessionId(),
}
end


local D=a.b(){
Request=b.Request,
ConnectWebSocket=b.ConnectWebSocket,
HttpService=o,
BridgeURL=f,
WebSocketAvailable=C,
GetRegistrationInfo=GetRegistrationInfo,
SanitizeForOutput=SanitizeForOutput,
LuaEncode=x,
}
local E=D.CreateBridge


local F=a.c()
local G=a.d()
local H=a.e()
local I=a.f()
local J=a.g()
local K=G.new()
local L=math.max(
1,
math.min(math.floor(tonumber(c.MCP_ScriptMappingWorkers)or 24),64)
)
local M=a.h().new(
K,
L
)
local N=math.max(
5,
math.min(tonumber(c.MCP_FailedScriptResyncInterval)or 30,600)
)
local O=a.i().new(K,{
IntervalSeconds=N,
MaxDelaySeconds=math.max(N,300),
BatchSize=math.max(
1,
math.min(math.floor(tonumber(c.MCP_FailedScriptResyncBatchSize)or 8),32)
),
})
local P=a.j().new(
K,
O
)
local Q=a.k(){
Request=b.Request,
ScriptMappingPipeline=K,
HttpService=o,
BridgeURL=f,
JobStatus=P,
}
local R=a.l(){
Request=b.Request,
ScriptMappingPipeline=K,
HttpService=o,
BridgeURL=f,
StripDecompilerBanner=StripDecompilerBanner,
base64_encode=r,
BuiltInDecompile=t,
GetScriptHash=s,
DecompilerAttemptState=I,
PreparedScript=J,
Concurrency=M,
}
local S=a.m(){
ScriptMappingPipeline=K,
WorkerPool=F,
UploadSession=H,
GenerateSessionGuid=GenerateSessionGuid,
CoreGui=l,
CorePackages=m,
ScriptContext=n,
getnilinstances=B,
WorkerCount=L,
Concurrency=M,
JobStatus=P,
FailedResync=O,
UploadClient=Q,
DecompilerClient=R,
}
local T=Q.StartUploadQueue
local function PublishScriptMappingStatus()
P:Publish()
end
local U=S.StartScriptMapping
local V=S.StartFailedScriptResync
local W=S.ResetScriptMappingState
local X=S.ResumeDeferredScriptMappings
local Y=S.GetScriptByDebugId
local Z=S.QueueMappedScriptSource
local aa=S.DecompileScriptSource

local function WaitForBridgeClientId(ab)
local ac=os.clock()+5
repeat
if ab.ClientId then
return ab.ClientId
end
if not ab.Connected then
return nil
end
task.wait(0.05)
until os.clock()>ac

return nil
end

c.MCP_Loaded=true a.u()
{
Compatibility=b,
Environment=c,
CreateBridge=E,
WaitForBridgeClientId=WaitForBridgeClientId,
IsCurrentConnector=IsCurrentConnector,
ScriptMappingPipeline=K,
StartUploadQueue=T,
PublishScriptMappingStatus=PublishScriptMappingStatus,
ResetScriptMappingState=W,
StartScriptMapping=U,
StartFailedScriptResync=V,
ResumeDeferredScriptMappings=X,
GetScriptByDebugId=Y,
DecompileScriptSource=aa,
QueueMappedScriptSource=Z,
LogService=p,
MarketplaceService=k,
RobloxReplicatedStorage=h,
VirtualInputManager=j,
LuaEncode=x,
}