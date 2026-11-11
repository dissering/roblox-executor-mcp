# Windsurf Setup

The harness installer configures Windsurf for you (`npm run install:harnesses -- --show-all-harnesses`, then select **Windsurf**).

Before setting it up by hand, build the server once from the repo root:

```bash
npm install
npm run build
```

## 1. Open the MCP config

In Windsurf, open the command palette (`Ctrl+Shift+P` / `Cmd+Shift+P`) and run **Windsurf: Open MCP Config**, or edit the file directly:

- **macOS / Linux:** `~/.codeium/windsurf/mcp_config.json`
- **Windows:** `%USERPROFILE%\.codeium\windsurf\mcp_config.json`

## 2. Add the MCP server

Add or merge the following:

```json
{
  "mcpServers": {
    "roblox-mcp": {
      "command": "node",
      "args": [
        "/path/to/roblox-executor-mcp/dist/index.js",
        "--server-name",
        "roblox-mcp"
      ]
    }
  }
}
```

Replace `/path/to/roblox-executor-mcp` with the absolute path where you cloned the repo.

## 3. Reload

Restart Windsurf or reload the window.

## Verify

Open Cascade and check that the `roblox-mcp` tools are listed. If the server isn't connecting:

- Confirm `dist/index.js` exists (run `npm run build`)
- Check the path in the config
- Confirm Node.js 18 or newer is installed (`node -v`)
