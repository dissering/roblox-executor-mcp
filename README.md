<p align="center">
  <img src="docs/banner-new.svg" alt="Roblox Executor MCP" width="900"/>
</p>

# Roblox Executor MCP Server

An MCP server that allows Agents to interact with a running Roblox game client — execute code, inspect scripts, spy on remotes, and more.

## Dashboard

Roblox Executor MCP includes a local web dashboard at:

```text
http://localhost:16384/
```

Use it to see connected Roblox clients, inspect scripts, run tools, view server logs, configure semantic search, and index games for semantic script search.

## Features

- **Code Execution** — Run Lua code and fetch data from the game client.
- **Script Inspection** — Decompile scripts and search across all sources.
- **Instance Search** — CSS-like selectors and hierarchy trees.
- **Remote Spy** — Intercept, log, block, and ignore Remotes/Bindables via [Cobalt](https://github.com/notpoiu/cobalt).
- **GUI Interaction** — Click buttons and type into text boxes.
- **Screenshot** — Capture Roblox window screenshots (Windows only).
- **Multi-Client** — Connect multiple Roblox clients at once.
- **Primary / Secondary** — Multiple MCP instances auto-coordinate with automatic promotion. Supports remote relaying via `--baseurl`. See [Advanced](docs/advanced.md).

## Tutorial

[![roblox-executor-mcp installation guide](http://img.youtube.com/vi/Tcy5RNf1TRc/0.jpg)](https://youtube.com/watch?v=Tcy5RNf1TRc)

## Prerequisites

- **Node.js** ≥ 18
- **Bun** ≥ 1.3 for the interactive OpenTUI harness installer
- **A Roblox executor** that supports `loadstring`, `request`, and (preferably) `WebSocket`

## Executor compatibility

The connector detects features instead of requiring a particular executor name or UNC percentage. `get-game-info` reports the executor name/version, environment source and available functions. Availability is not a claim that a function passes sUNC or grants additional permissions.

- Required: `loadstring`, HTTP access through `request`, `http_request`, `syn.request` or `http.request`, and basic Roblox instance/service access.
- Missing or failing `getgenv` falls back to `_G` or the script environment. `cloneref` is optional, and a broken `getnilinstances` does not stop ordinary script scanning. Detached scripts cannot be discovered without working enumeration.
- Missing or failing identity setters leave the executor's current permissions in place. This keeps basic execution working; restricted APIs may still fail. Both MCP and dashboard execution use the same connector-side handling.
- WebSocket aliases are supported, with HTTP polling as the fallback. The loader can also download through an HTTP request alias when `game:HttpGet` fails.
- Without `firesignal`, button clicks use VirtualInputManager when permitted. This converts GUI positions to screen coordinates using [Roblox's GUI inset](https://create.roblox.com/docs/reference/engine/classes/GuiBase2d#AbsolutePosition), then sends mouse input to a visible, unobstructed button; down-only signal actions still require `firesignal`. An unavailable input service disables that feature rather than the whole connector.
- Cobalt remote spying requires native hooking APIs. Missing prerequisites return a specific error before loading Cobalt; the bridge does not invent replacements for unsupported hooks.

Update both the server and the connector (rerun the loader in a fresh Roblox client) to use connector-side identity handling.

These paths are tested with missing and throwing APIs, including the limitations in the supplied Xeno v1.3.30 sUNC report. Live compatibility probes ran on Xeno v1.3.65, including an observed click on a temporary test button without `firesignal`. Failed sUNC tests can still expose callable functions, so operations are protected at runtime rather than classified by score alone.

## Quick Start

### 1. Clone the server

```bash
git clone https://github.com/dissering/roblox-executor-mcp.git
cd roblox-executor-mcp
```

### 2. Run the harness installer

The installer builds the server, lets you choose AI clients, writes supported MCP configs, and prints the Roblox loader script.

```bash
npm run install:harnesses
```

The normal server build consumes the committed `connector.luau` artifact, so harness installs do not require Darklua. Connector developers can install the pinned tool with `rokit install`, edit `connector-src/`, and regenerate the artifact with `npm run build:connector`.

The picker is built with [OpenTUI](https://opentui.com/) and runs through Bun. `npm run install:harnesses` installs Bun first if it is not already available. It shows detected local clients by default; if none are detected, it warns you to install a harness first. Press `s` in the picker or pass `--show-all-harnesses` to reveal every supported config target. If your terminal has trouble with the interactive picker, use the plain numbered prompt:

```bash
npm run install:harnesses -- --plain
```

The installer can also place the Roblox loader into a detected executor autoexec folder, such as MacSploit on macOS or supported Windows executor autoexec folders. Use the prompt, or run:

```bash
npm run getscript -- --autoexec
```

It can also help with:

- cross-machine setup on the same LAN
- copying the Roblox loader to your clipboard
- optional Ollama `embeddinggemma` setup for semantic indexing
- pulling latest repo changes before install/build

To update an existing install later, run:

```bash
npm run update
```

The update command can stop currently running MCP server processes, optionally pull latest changes, and always rebuilds the server.

### Manual setup

If you prefer to configure a client yourself, use the setup guide for your client:

| Client         | Guide                                       |
| -------------- | ------------------------------------------- |
| Cursor         | [Setup Guide](docs/setup-cursor.md)         |
| Claude Desktop | [Setup Guide](docs/setup-claude-desktop.md) |
| Claude Code    | [Setup Guide](docs/setup-claude-code.md)    |
| Codex CLI      | [Setup Guide](docs/setup-codex.md)          |
| Windsurf       | [Setup Guide](docs/setup-windsurf.md)       |
| Antigravity    | [Setup Guide](docs/setup-antigravity.md)    |
| BLACKBOX AI    | [Setup Guide](docs/setup-blackbox.md)       |
| ZCode          | [Setup Guide](docs/setup-zcode.md)          |

### 3. Connect from Roblox

The installer prints this for you. Put it in your executor or Auto Execute:

```lua
local environment = _G
if type(getgenv) == "function" then
    local ok, value = pcall(getgenv)
    if ok and type(value) == "table" then environment = value end
end
if type(environment) ~= "table" then environment = getfenv(0) end
local lastError
while not environment.MCP_Loaded do
    local bridgeUrl = environment.BridgeURL or environment.bridgeurl or "localhost:16384"
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
end
```

**Optional settings** (set before running the loader; use `_G` instead of `getgenv()` when `getgenv` is unavailable):

```lua
getgenv().BridgeURL = "10.0.0.4:16384"                  -- default: localhost:16384
getgenv().DisableWebSocket = true                        -- force HTTP polling
getgenv().DisableInitialScriptDecompMapping = true       -- skip initial decompilation
getgenv().MCP_FailedScriptResyncInterval = 30            -- retry failed script syncs periodically
getgenv().MCP_FailedScriptResyncBatchSize = 8            -- bound each periodic retry batch
```

After the MCP server starts and Roblox connects, open the dashboard:

```text
http://localhost:16384/
```

## Community

Have a suggestion or need help? Join the [Discord server](https://discord.gg/FJcJMuze7S).

## Security

> **This server allows arbitrary code execution.** Only use with AI clients you trust. Port `16384` has no authentication — **never expose it to the internet.** For cross-machine setups, use a local network, VPN, or SSH tunnel. See [Advanced](docs/advanced.md) for details.

## License

[MIT](LICENSE)
