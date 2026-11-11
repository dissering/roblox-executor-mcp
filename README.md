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

- **Code Execution** — Run Luau code or a local file and fetch data from the game client.
- **Script Inspection** — Decompile scripts, read line ranges, and grep across all sources.
- **Semantic Search** — Find scripts by behavior with a local embedding index (Ollama `embeddinggemma` or another provider).
- **Console Output** — Read the client's output log.
- **Instance Search** — CSS-like selectors and hierarchy trees.
- **Remote Spy** — Built-in spy that logs, blocks, ignores, and generates replay code for remote calls. Uses the strongest hook your executor has and still logs incoming events on executors without hooks.
- **GUI Interaction** — Click buttons and type into text boxes.
- **Screenshot** — Capture Roblox window screenshots (Windows only).
- **Multi-Client** — Connect multiple Roblox clients at once.
- **Primary / Secondary** — Multiple MCP instances auto-coordinate with automatic promotion. Supports remote relaying via `--baseurl`. See [Advanced](docs/advanced.md).

## Tools

| Tool | What it does |
| --- | --- |
| `list-clients` / `set-active-client` | List connected Roblox clients and choose which one tools target |
| `execute` / `execute-file` | Run Luau source, or a local `.luau` file, in the client |
| `get-data-by-code` | Run Luau and return its result |
| `get-game-info` | Place, job, executor name/version, and detected executor functions |
| `get-console-output` | Recent client output log entries |
| `search-instances` | Find instances with CSS-like selectors |
| `get-descendants-tree` | Hierarchy tree of an instance |
| `get-script-content` | Decompiled source of a script, optionally a line range |
| `script-grep` | Regex or literal search across all mapped script sources |
| `semantic-search-scripts` | Search scripts by behavior using the semantic index |
| `remote-spy` | Log, block, ignore, and replay remote calls (outgoing and incoming) |
| `click-button` / `type-text-box` | Interact with GUI buttons and text boxes |
| `list-roblox-windows` / `screenshot-window` | List and capture Roblox windows (Windows only) |

## Tutorial

[![roblox-executor-mcp installation guide](http://img.youtube.com/vi/Tcy5RNf1TRc/0.jpg)](https://youtube.com/watch?v=Tcy5RNf1TRc)

## Prerequisites

- **Node.js** ≥ 18 (≥ 22 to run the test suite)
- **Bun** ≥ 1.3 for the interactive OpenTUI harness installer (installed automatically if missing)
- **A Roblox executor** that supports `loadstring`, `request`, and (preferably) `WebSocket`

## Executor compatibility

The connector detects features instead of requiring a particular executor name or UNC percentage. `get-game-info` reports the executor name/version, environment source and available functions. Availability is not a claim that a function passes sUNC or grants additional permissions.

- Required: `loadstring`, HTTP access through `request`, `http_request`, `syn.request` or `http.request`, and basic Roblox instance/service access.
- Missing or failing `getgenv` falls back to `_G` or the script environment. `cloneref` is optional, and a broken `getnilinstances` does not stop ordinary script scanning. Detached scripts cannot be discovered without working enumeration.
- Missing or failing identity setters leave the executor's current permissions in place. This keeps basic execution working; restricted APIs may still fail. Both MCP and dashboard execution use the same connector-side handling.
- WebSocket aliases are supported, with HTTP polling as the fallback. The loader can also download through an HTTP request alias when `game:HttpGet` fails.
- Without `firesignal`, button clicks use VirtualInputManager when permitted. This converts GUI positions to screen coordinates using [Roblox's GUI inset](https://create.roblox.com/docs/reference/engine/classes/GuiBase2d#AbsolutePosition), then sends mouse input to a visible, unobstructed button; down-only signal actions still require `firesignal`. An unavailable input service disables that feature rather than the whole connector.
- The remote spy picks its outgoing mode from what the executor supports: `hookmetamethod` + `getnamecallmethod`, then a raw metatable swap (`getrawmetatable` + `setreadonly`), then `hookfunction` on `FireServer`/`InvokeServer`. Incoming `OnClientEvent` traffic is logged on every executor, with no hooks needed. Blocking incoming events needs `getconnections`. `remote-spy` with `operation=status` reports the active modes and what is missing.

Update both the server and the connector (rerun the loader in a fresh Roblox client) to use connector-side identity handling.

These paths are tested with missing and throwing APIs, including the limitations in the supplied Xeno v1.3.30 sUNC report. Live compatibility probes ran on Xeno v1.3.65, including an observed click on a temporary test button without `firesignal`. Failed sUNC tests can still expose callable functions, so operations are protected at runtime rather than classified by score alone.

## Quick Start

### 1. Clone the server

```bash
git clone https://github.com/dissering/roblox-executor-mcp.git
cd roblox-executor-mcp
```

### 2. Run the harness installer

The installer builds the server, lets you choose AI clients, writes supported MCP configs, and prints the Roblox loader script. It supports Codex, Claude Code, OpenCode, Cursor, Trae, Antigravity, Gemini CLI, GitHub Copilot, VS Code Copilot, Claude Desktop, Windsurf, Cline, Continue, ZCode, BLACKBOX AI, and more. It backs up any config file it edits to a `.bak` copy first.

```bash
npm run install:harnesses
```

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
| OpenCode       | [Setup Guide](docs/setup-opencode.md)       |
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
getgenv().MCP_ScriptMappingWorkers = 24                  -- concurrent decompile workers (1-64)
```

See [Advanced](docs/advanced.md#connector-options) for the full list and limits.

**Quick loader from GitHub:** [`mcp.lua`](mcp.lua) holds every setting above plus a `loadstring` of the published `connector.luau`, so you can paste one file into your executor without the server serving the script:

```lua
getgenv().BridgeURL = "100.84.48.89:16384"

loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/dissering/roblox-executor-mcp/main/connector.luau"
))()
```

This pulls the connector from the `main` branch, so keep your local server up to date with `npm run update`. If the two drift apart, use the loader above, which downloads the connector from your own server.

After the MCP server starts and Roblox connects, open the dashboard:

```text
http://localhost:16384/
```

## Development

```bash
npm install
npm run build          # TypeScript server into dist/
npm run dev            # start the local dev server
```

The server build uses the committed `connector.luau`, so normal installs do not need Darklua. To change the Roblox connector, edit `connector-src/`, install the pinned toolchain with `rokit install`, and regenerate the bundle:

```bash
npm run build:connector
```

Commit the regenerated `connector.luau` together with the `connector-src/` change.

`npm test` builds everything, then runs the Node tests and the Luau tests. It needs `darklua` and the [`luau`](https://github.com/luau-lang/luau/releases) CLI on your `PATH`.

## Troubleshooting

- **Client never shows up:** check that the loader's `BridgeURL` matches the machine running the server, and that nothing else uses port `16384`. Open `http://localhost:16384/` to confirm the server is up.
- **MCP client shows the server as failed:** run `npm run build` and check the absolute path to `dist/index.js` in its config.
- **Executor without WebSocket:** the connector falls back to HTTP polling automatically. Set `DisableWebSocket = true` to force it.
- **Tools time out after reconnecting Roblox:** rerun the loader in a fresh client after updating the server so the connector and server match.

## Community

Have a suggestion or need help? Join the [Discord server](https://discord.gg/FJcJMuze7S).

## Security

> **This server allows arbitrary code execution.** Only use with AI clients you trust. Port `16384` has no authentication — **never expose it to the internet.** For cross-machine setups, use a local network, VPN, or SSH tunnel. See [Advanced](docs/advanced.md) for details.

## License

[MIT](LICENSE)
