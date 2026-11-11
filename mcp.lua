-- Roblox Executor MCP quick loader.
-- Edit the settings, then run this in your executor or put it in autoexec.
-- Every setting is optional. Delete a line to use its default.

local env = (type(getgenv) == "function" and getgenv()) or _G

env.BridgeURL = "localhost:16384"                 -- host:port of the machine running the MCP server
env.DisableWebSocket = false                      -- true forces HTTP polling
env.DisableInitialScriptDecompMapping = false     -- true skips decompiling every script on connect
env.MCP_ScriptMappingWorkers = 24                 -- concurrent decompile workers, 1 to 64
env.MCP_FailedScriptResyncInterval = 30           -- seconds before retrying failed scripts, 5 to 600
env.MCP_FailedScriptResyncBatchSize = 8           -- failed scripts retried per tick, 1 to 32

loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/dissering/roblox-executor-mcp/main/connector.luau"
))()
