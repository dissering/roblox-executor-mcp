-- Roblox Executor MCP quick loader.
-- Edit the settings, then run this in your executor or put it in autoexec.
-- Every setting is optional. Delete a line to use its default.

local Settings = {
    BridgeURL = "localhost:16384",                -- host:port of the machine running the MCP server
    DisableWebSocket = false,                     -- true forces HTTP polling
    DisableInitialScriptDecompMapping = false,    -- true skips decompiling every script on connect
    MCP_ScriptMappingWorkers = 24,                -- concurrent decompile workers, 1 to 64
    MCP_FailedScriptResyncInterval = 30,          -- seconds before retrying failed scripts, 5 to 600
    MCP_FailedScriptResyncBatchSize = 8,          -- failed scripts retried per tick, 1 to 32
}

-- Copy the settings onto every global table. Run-on-attach and manual runs can see
-- different globals, and the connector also receives Settings directly below.
local env = _G
if type(getgenv) == "function" then
    local ok, value = pcall(getgenv)
    if ok and type(value) == "table" then env = value end
end
for _, target in { env, _G, type(shared) == "table" and shared or nil } do
    for name, value in Settings do
        pcall(function() target[name] = value end)
    end
end

local CONNECTOR_URL = "https://raw.githubusercontent.com/dissering/roblox-executor-mcp/main/connector.luau"

-- Some executors (Athena) have no game:HttpGet, so fall back to their HTTP request function.
local function download(url)
    local ok, body = pcall(function()
        return game:HttpGet(url)
    end)
    if ok and type(body) == "string" then
        return body
    end

    local send
    for _, candidate in { request, http_request, type(syn) == "table" and syn.request, type(http) == "table" and http.request } do
        if type(candidate) == "function" then
            send = candidate
            break
        end
    end
    assert(send, "MCP loader: executor has neither game:HttpGet nor an HTTP request function.")

    local response = send({ Url = url, Method = "GET" })
    local status = type(response) == "table"
        and tonumber(response.StatusCode or response.Status or response.status_code or response.status)
    assert(status == 200, "MCP loader: connector download failed with status " .. tostring(status))
    return response.Body or response.body
end

print("[roblox-mcp] loader running, downloading connector for " .. tostring(Settings.BridgeURL))
local source = download(CONNECTOR_URL)
local chunk, compileError = loadstring(source)
assert(chunk, "MCP loader: " .. tostring(compileError))
chunk(Settings)
