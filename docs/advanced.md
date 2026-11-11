# Advanced Configuration

## Primary / Secondary Mode

By default, the server starts as a **primary** on port `16384`. If that port is already in use, it automatically becomes a **secondary** that relays all tool calls through the primary. When the primary disconnects, a secondary will promote itself automatically.

### Remote primary (`--baseurl`)

If your AI client runs on macOS/Linux but Roblox is on a Windows machine, you can relay through a remote primary:

```json
{
  "mcpServers": {
    "roblox-mcp": {
      "command": "node",
      "args": [
        "/path/to/roblox-executor-mcp/dist/index.js",
        "--server-name",
        "roblox-mcp",
        "--baseurl",
        "http://<windows-ip>:16384"
      ]
    }
  }
}
```

**Fallback behavior:**

| Scenario | Result |
|---|---|
| Remote reachable | Secondary relay to remote host |
| Remote unreachable | Falls back to primary locally |
| Remote unreachable + local port taken | Secondary to local primary |

> `screenshot-window` and `list-roblox-windows` are forwarded over HTTP to the primary, so a Mac secondary can capture windows on a Windows primary.

Each relayed request gets its own routing ID on the primary, so several secondaries can run tool calls at the same time without receiving each other's responses. Pending calls from a secondary fail immediately if its relay connection drops instead of waiting for the timeout.

## Server Options

| Flag / variable | Default | Description |
|---|---|---|
| `--baseurl <url>` | none | Run as a secondary relaying to the primary at `<url>` (see above) |
| `--server-name <name>` | `roblox-mcp` | Name the server reports to the MCP client |
| `ROBLOX_MCP_SERVER_NAME` | `roblox-mcp` | Same as `--server-name`; the flag wins if both are set |

## Connector Options

Set these in Roblox **before** running the connector:

| Variable | Default | Description |
|---|---|---|
| `getgenv().BridgeURL` | `localhost:16384` | Server address to connect to |
| `getgenv().DisableWebSocket` | `false` | Force HTTP polling instead of WebSocket |
| `getgenv().DisableInitialScriptDecompMapping` | `false` | Skip decompiling all scripts on connect |
| `getgenv().MCP_FailedScriptResyncInterval` | `30` | Seconds before the first failed-script resync; repeated failures back off to five minutes |
| `getgenv().MCP_FailedScriptResyncBatchSize` | `8` | Maximum failed scripts queued by one periodic resync tick (1 to 32) |
| `getgenv().MCP_ScriptMappingWorkers` | `24` | Concurrent decompile workers during script mapping (1 to 64) |

Use `_G` in place of `getgenv()` on executors without a working `getgenv`. `MCP_FailedScriptResyncInterval` is clamped to 5 to 600 seconds.

Failed script mappings are retried automatically in bounded batches. A resync prioritizes the provider that the original attempt actually reached, then uses the configured provider order as fallback.

The connector supports two transport modes:
- **WebSocket** (preferred) — persistent connection, lower latency
- **HTTP Polling** — fallback for executors that don't support WebSocket, or when WebSocket registration fails

When the connection drops, the connector tears down the old bridge (heartbeat, poll loop, in-flight commands, socket listeners) before reconnecting, so repeated reconnects do not pile up threads.

## Remote Spy

The connector has its own remote spy. It starts the first time `remote-spy` is called and stays installed for the Roblox session, including across bridge reconnects.

| Capability | Executor APIs used | Without them |
|---|---|---|
| Outgoing `FireServer` / `InvokeServer` logging and blocking | `hookmetamethod` + `getnamecallmethod`, or `getrawmetatable` + `setreadonly` + `getnamecallmethod`, plus `hookfunction` for direct calls | Falls back to the next option. With none, outgoing calls are not captured |
| Calling script, executor-call filtering | `getcallingscript`, `checkcaller` | Fields are left empty and executor calls are logged |
| Incoming `OnClientEvent` logging | None | Always available |
| Incoming blocking | `getconnections` | Events are logged but not blocked |

Notes:

- Block and ignore rules match exact remote names and apply to remotes that have not fired yet.
- Executor calls, including replays, are never logged or blocked unless `includeExecutorCalls` is turned on with `operation=configure`.
- Bindables are off by default. Turn them on with `includeBindables`.
- Each remote keeps its last 50 calls. With `summaryOnly=false`, every call includes its arguments, calling script, and a `Replay` snippet you can run with `execute`.

## Dashboard

A local dashboard is available at `http://localhost:16384/` while the server runs. It shows connected clients, server role and uptime, and lets you browse scripts, run tools, read server logs, set up harnesses, pick a theme, configure decompilers, and build the semantic search index.

Under **Settings → Decompiler fallbacks**, choose **Add provider → Custom provider** to add an HTTP decompiler to the fallback chain. You can add multiple custom providers; each keeps an independent workflow, fallback position, endpoint, authentication, headers, timeout, and health state. The custom-provider editor uses a pannable, zoomable node canvas: add blocks, drag them into place, and connect their ports to define the bytecode-to-source path. Bytecode and Source are permanent boundary blocks. Use Set Variable to name the current raw or base64 value, then reference it in the Request headers or body with `{{variable_name}}`; the optional API key is available as `{{api_key}}`. Type `{{` for autocomplete, use the arrow keys to choose a variable, and press Enter or Tab to insert it. Undo and redo are available from the toolbar or with Command/Ctrl+Z, Command/Ctrl+Shift+Z, and Ctrl+Y. The Request response port can connect directly to Source for plain text or through Parse JSON for a configurable dot-path field.

## Security

**This server allows arbitrary code execution.** Any connected AI client can run Lua code in your Roblox session, take screenshots, and read client data.

**Never expose port `16384` to the internet.** There is no authentication. For cross-machine setups:

- Use a **local network** or **VPN**
- Use an **SSH tunnel**: `ssh -L 16384:localhost:16384 user@windows-machine`
- **Never** forward the port through a public router or cloud firewall
