local Compat = {}

function Compat.GetEnvironment(runtime)
    if type(runtime.getgenv) == "function" then
        local ok, environment = pcall(runtime.getgenv)
        if ok and type(environment) == "table" then return environment, "getgenv" end
    end
    if type(runtime._G) == "table" then return runtime._G, "_G" end
    return runtime, "script"
end

function Compat.new(runtime)
    runtime = runtime or getfenv(0)
    local environment, environmentMode = Compat.GetEnvironment(runtime)
    local function lookup(name)
        local value = environment[name]
        if value == nil then value = runtime[name] end
        return value
    end
    local function nested(namespace, name)
        local owner = lookup(namespace)
        return type(owner) == "table" and owner[name] or nil
    end
    local function firstFunction(...)
        for i = 1, select("#", ...) do
            local value = select(i, ...)
            if type(value) == "function" then return value end
        end
        return nil
    end

    local requestFunction = firstFunction(lookup("request"), lookup("http_request"), nested("syn", "request"), nested("http", "request"))
    local setIdentity = firstFunction(lookup("setthreadidentity"), lookup("setidentity"), nested("syn", "set_thread_identity"))
    local cloneReference = firstFunction(lookup("cloneref"))
    local nilInstances = firstFunction(lookup("getnilinstances"))
    local connectWebSocket = firstFunction(nested("WebSocket", "connect"), nested("websocket", "connect"))
    local info = {
        name = "Unknown", version = "", environment = environmentMode,
        available = {
            getgenv = environmentMode == "getgenv", request = requestFunction ~= nil, websocket = connectWebSocket ~= nil,
            setthreadidentity = setIdentity ~= nil, cloneref = cloneReference ~= nil,
            getnilinstances = nilInstances ~= nil,
        },
    }
    for _, name in { "loadstring", "decompile", "getscriptbytecode", "getconnections", "firesignal", "hookmetamethod", "hookfunction", "getnamecallmethod", "newcclosure", "checkcaller" } do
        info.available[name] = type(lookup(name)) == "function"
    end
    local identify = firstFunction(lookup("identifyexecutor"), lookup("getexecutorname"))
    if identify then
        local ok, name, version = pcall(identify)
        if ok then
            info.name = tostring(name or "Unknown")
            info.version = tostring(version or "")
        end
    end

    local api = { Environment = environment, Info = info, ConnectWebSocket = connectWebSocket }

    function api.Request(options)
        assert(requestFunction, "This executor needs request, http_request, syn.request or http.request to connect to MCP.")
        local response = requestFunction(options)
        assert(type(response) == "table", "Executor HTTP request returned no response table.")
        return {
            StatusCode = tonumber(response.StatusCode or response.Status or response.status_code or response.status),
            Body = response.Body or response.body,
            Headers = response.Headers or response.headers or {},
        }
    end

    function api.SetThreadIdentity(identity)
        if not setIdentity then return false end
        local ok = pcall(setIdentity, identity or 8)
        if not ok then info.available.setthreadidentity = false end
        -- Keep the executor's existing permissions when an optional identity setter is unavailable.
        return ok
    end

    function api.CloneReference(instance)
        if cloneReference then
            local ok, reference = pcall(cloneReference, instance)
            if ok and reference ~= nil then return reference end
            info.available.cloneref = false
        end
        return instance
    end

    function api.GetNilInstances()
        if nilInstances then
            local ok, instances = pcall(nilInstances)
            if ok and type(instances) == "table" then return instances end
            info.available.getnilinstances = false
        end
        return {}
    end

    function api.RequireRemoteSpySupport()
        local missing = {}
        for _, name in { "hookmetamethod", "hookfunction", "getnamecallmethod", "newcclosure", "checkcaller" } do
            if not info.available[name] then table.insert(missing, name) end
        end
        assert(#missing == 0, "Remote spying is unavailable on this executor: missing " .. table.concat(missing, ", ") .. ". Execution, inspection and decompilation remain available.")
    end

    return api
end

return Compat
