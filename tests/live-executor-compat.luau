-- Run this bounded probe through an existing MCP connection. It does not replace that connection.
local Compat = require("../connector-src/compat")
local RegisterCore = require("../connector-src/bridge/handlers/core")
local RegisterInstances = require("../connector-src/bridge/handlers/instances")

local isolatedEnvironment = {}
local compat = Compat.new({
    _G = isolatedEnvironment,
    getgenv = function() error("simulated unsupported getgenv") end,
    setthreadidentity = function() error("simulated unsupported identity setter") end,
    cloneref = function() error("simulated unsupported cloneref") end,
    getnilinstances = function() error("simulated unsupported nil-instance enumeration") end,
    http_request = request,
    identifyexecutor = identifyexecutor,
    loadstring = loadstring,
})
local callbacks = {}
local bridge = {
    BindToType = function(_, name, callback) callbacks[name] = callback end,
    BindToTypeRaw = function(_, name, callback) callbacks[name] = callback end,
}
RegisterCore({ Compatibility = compat, LogService = game:GetService("LogService") }, bridge)
RegisterInstances({ Compatibility = compat, MarketplaceService = game:GetService("MarketplaceService") }, bridge)
local values = callbacks["get-data-by-code"]({ source = "return 6 * 7, false, nil", threadContext = 8 })
local info = callbacks["get-game-info"]({})
local response = compat.Request({ Url = "http://localhost:16384/", Method = "GET" })
local _, spyError = pcall(compat.RequireRemoteSpySupport)
return {
    executor = info.Executor.name,
    version = info.Executor.version,
    environmentFallback = compat.Environment == isolatedEnvironment,
    identityFailureIsolated = not compat.Info.available.setthreadidentity,
    returnValues = values[1] == 42 and values[2] == false and values.n == 3,
    nilEnumerationFailureIsolated = #compat.GetNilInstances() == 0,
    referenceFailureIsolated = compat.CloneReference(game) == game,
    requestAlias = response.StatusCode == 200,
    gameInfoWithoutPrivateService = info.PlaceId == game.PlaceId and info.ServerType == "Unknown",
    remoteSpyUnsupported = type(spyError) == "string" and string.find(spyError, "missing", 1, true) ~= nil,
}
