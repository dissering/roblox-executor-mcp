local Compat = require("../connector-src/compat")
local RegisterCore = require("../connector-src/bridge/handlers/core")
local RegisterInput = require("../connector-src/bridge/handlers/input")

local shared = {}
local weak = Compat.new({ _G = shared })
assert(weak.Environment == shared and weak.Info.environment == "_G")
assert(not weak.Info.available.getgenv and not weak.Info.available.request)
assert(not weak.SetThreadIdentity(8))
assert(#weak.GetNilInstances() == 0)
local instance = {}
assert(weak.CloneReference(instance) == instance)
local requestOk, requestError = pcall(weak.Request, {})
assert(not requestOk and string.find(requestError, "http_request", 1, true))

local rejected = Compat.new({
    _G = shared,
    getgenv = function() error("unsupported") end,
    setthreadidentity = function() error("unsupported") end,
    cloneref = function() error("unsupported") end,
    getnilinstances = function() error("unsupported") end,
})
assert(rejected.Environment == shared)
assert(not rejected.SetThreadIdentity(8) and rejected.Info.available.setthreadidentity == false)
assert(rejected.CloneReference(instance) == instance and rejected.Info.available.cloneref == false)
assert(#rejected.GetNilInstances() == 0 and rejected.Info.available.getnilinstances == false)
assert(Compat.new({ getgenv = function() return false end }).Info.environment == "script")

local identity
local alias = Compat.new({
    _G = {},
    http_request = function(options)
        assert(options.Url == "http://localhost/test")
        return { status_code = 200, body = "ok", headers = { test = "yes" } }
    end,
    setidentity = function(value) identity = value end,
    websocket = { connect = function() return "socket" end },
})
local response = alias.Request({ Url = "http://localhost/test" })
assert(response.StatusCode == 200 and response.Body == "ok" and response.Headers.test == "yes")
assert(alias.SetThreadIdentity(4) and identity == 4)
assert(alias.ConnectWebSocket() == "socket")

for _, runtime in {
    { syn = { request = function() return { StatusCode = 200, Body = "syn" } end } },
    { http = { request = function() return { status = 200, body = "http" } end } },
} do
    assert(Compat.new(runtime).Request({}).StatusCode == 200)
end

local calls = 0
local throwingRequest = Compat.new({ request = function() calls += 1; error("network failure") end })
assert(not pcall(throwingRequest.Request, {}))
assert(calls == 1, "HTTP requests must not be replayed after an uncertain failure")
assert(not pcall(weak.RequireRemoteSpySupport), "missing hooks must produce a feature-specific error")

-- Basic handlers remain usable even when an executor has no identity setter.
local callbacks = {}
local bridge = {
    BindToType = function(_, name, callback) callbacks[name] = callback end,
    BindToTypeRaw = function(_, name, callback) callbacks[name] = callback end,
}
local compiled, ran
RegisterCore({
    Compatibility = weak,
    LogService = { GetLogHistory = function() return {} end },
}, bridge)
local handlerEnvironment = getfenv(RegisterCore)
handlerEnvironment.loadstring = function(source)
    compiled = source
    if source == "invalid" then return nil, "syntax failure" end
    return function() ran = true; return 42, false, nil end
end
handlerEnvironment.task = { defer = function(callback) callback() end }
local values = callbacks["get-data-by-code"]({ source = "return values", threadContext = 8 })
assert(compiled == "return values" and values.n == 3 and values[1] == 42 and values[2] == false and values[3] == nil)
callbacks.execute({ source = "print something" })
assert(ran and compiled == "print something")
local compileOk, compileError = pcall(callbacks["get-data-by-code"], { source = "invalid" })
assert(not compileOk and string.find(compileError, "syntax failure", 1, true))

-- The input fallback sends a click only when the selected action can be represented.
local mouseEvents = {}
RegisterInput({ GuiService = { GetGuiInset = function() return {X=0, Y=36} end }, VirtualInputManager = {
    SendMouseMoveEvent = function(_, x, y)
        assert(x == 50 and y == 76)
    end,
    SendMouseButtonEvent = function(_, x, y, button, down)
        table.insert(mouseEvents, {x=x, y=y, button=button, down=down})
    end,
} }, bridge)
local inputEnvironment = getfenv(RegisterInput)
inputEnvironment.task = { wait = function() end }
inputEnvironment.typeof = function(value)
    if type(value) == "table" and value.IsA then return "Instance" end
    return type(value)
end
local function vector(x, y)
    return setmetatable({ X=x, Y=y }, {
        __div = function(v, n) return vector(v.X/n, v.Y/n) end,
        __add = function(a, b) return vector(a.X+b.X, a.Y+b.Y) end,
    })
end
local button = { Visible = true, AbsolutePosition = vector(10,20), AbsoluteSize = vector(80,40), IsA = function() return true end }
local result = callbacks["click-button"]({ path = button })
assert(result.method == "virtual-input" and #mouseEvents == 2)
assert(mouseEvents[1].x == 50 and mouseEvents[1].y == 76 and mouseEvents[1].down and not mouseEvents[2].down)
assert(not pcall(callbacks["click-button"], { path = button, action = "MouseButton1Down" }))
assert(#mouseEvents == 2, "unsupported actions must not inject any mouse event")
button.Visible = false
assert(not pcall(callbacks["click-button"], { path = button }))
assert(#mouseEvents == 2)

RegisterInput({ VirtualInputManager = nil }, bridge)
button.Visible = true
assert(not pcall(callbacks["click-button"], { path = button }))
print("executor compatibility tests passed")
