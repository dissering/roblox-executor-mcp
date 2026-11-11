-- Roblox Executor MCP loader. Set BridgeURL to the host:port of the MCP server.
local BridgeURL = "localhost:16384"

local url = "https://raw.githubusercontent.com/dissering/roblox-executor-mcp/main/connector.luau"
local ok, source = pcall(function() return game:HttpGet(url) end)
if not ok or type(source) ~= "string" then
    -- Some executors (Athena) have no game:HttpGet.
    local send = request or http_request or (syn and syn.request) or (http and http.request)
    source = send({ Url = url, Method = "GET" }).Body
end
loadstring(source)({ BridgeURL = BridgeURL })
