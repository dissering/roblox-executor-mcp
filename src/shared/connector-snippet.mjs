export const DEFAULT_BRIDGE_URL = "localhost:16384";
export const SERVER_PORT = 16384;

export function normalizeBridgeUrl(value) {
  const trimmed = String(value || "").trim().replace(/\/+$/, "");
  if (!trimmed) return DEFAULT_BRIDGE_URL;
  const withProtocol = /^https?:\/\//i.test(trimmed) ? trimmed : `http://${trimmed}`;
  try {
    const url = new URL(withProtocol);
    if (!url.port) url.port = String(SERVER_PORT);
    return `${url.hostname}:${url.port}`;
  } catch {
    return DEFAULT_BRIDGE_URL;
  }
}

export function buildLoaderSnippet(bridgeUrl = DEFAULT_BRIDGE_URL) {
  const normalized = normalizeBridgeUrl(bridgeUrl);
  return `local environment = _G
if type(getgenv) == "function" then
    local ok, value = pcall(getgenv)
    if ok and type(value) == "table" then environment = value end
end
if type(environment) ~= "table" then environment = getfenv(0) end
${normalized === DEFAULT_BRIDGE_URL ? '' : `environment.BridgeURL = ${JSON.stringify(normalized)}\n`}local lastError
while not environment.MCP_Loaded do
    local bridgeUrl = environment.BridgeURL or environment.bridgeurl or "${DEFAULT_BRIDGE_URL}"
    local ok, failure = pcall(function()
        local downloaded, source = pcall(function() return game:HttpGet("http://" .. bridgeUrl .. "/script.luau") end)
        if not downloaded or type(source) ~= "string" then
            local send
            for _, candidate in {request, http_request, type(syn) == "table" and syn.request, type(http) == "table" and http.request} do
                if type(candidate) == "function" then send = candidate; break end
            end
            assert(send, "Executor has neither a working HttpGet nor an HTTP request function.")
            local response = send({Url = "http://" .. bridgeUrl .. "/script.luau", Method = "GET"})
            assert(type(response) == "table" and tonumber(response.StatusCode or response.Status or response.status_code or response.status) == 200, "Connector download failed.")
            source = response.Body or response.body
        end
        assert(type(loadstring) == "function", "Executor needs loadstring to load MCP.")
        local chunk, compileError = loadstring(source)
        assert(chunk, compileError)
        chunk()
    end)
    if not ok and tostring(failure) ~= lastError then
        lastError = tostring(failure)
        warn("MCP connector: " .. lastError)
    end
    task.wait(1)
end`;
}
