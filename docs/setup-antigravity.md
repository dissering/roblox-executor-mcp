# Antigravity Setup

The harness installer configures Antigravity for you (`npm run install:harnesses`, then select **Antigravity**).

Before setting it up by hand, build the server once from the repo root:

```bash
npm install
npm run build
```

## 1. Open the MCP config

In Antigravity, open the command palette (`Ctrl+Shift+P` / `Cmd+Shift+P`) and run **Antigravity: Manage MCP Servers**, then click **View raw config**. Or edit the file directly:

- **macOS / Linux:** `~/.gemini/antigravity/mcp_config.json`
- **Windows:** `%USERPROFILE%\.gemini\config\mcp_config.json`

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

Click **Refresh** next to **View raw config**.

## Verify

Check that the `roblox-mcp` tools are available in the agent panel. If the server isn't connecting:

- Confirm `dist/index.js` exists (run `npm run build`)
- Check the path in the config
- Confirm Node.js 18 or newer is installed (`node -v`)
