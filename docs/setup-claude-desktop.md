# Claude Desktop Setup

The harness installer configures Claude Desktop for you (`npm run install:harnesses -- --show-all-harnesses`, then select **Claude Desktop**). On Windows it writes both the classic and the Microsoft Store (MSIX) config locations.

Before setting it up by hand, build the server once from the repo root:

```bash
npm install
npm run build
```

## 1. Open the config file

In Claude Desktop, open **Settings → Developer → Edit Config**, or open the file directly:

- **macOS:** `~/Library/Application Support/Claude/claude_desktop_config.json`
- **Windows (classic installer):** `%APPDATA%\Claude\claude_desktop_config.json`
- **Windows (Microsoft Store):** `%LOCALAPPDATA%\Packages\Claude_pzs8sxrjxfjjc\LocalCache\Roaming\Claude\claude_desktop_config.json`

If the file doesn't exist, create it.

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

**Windows example:**

```json
{
  "mcpServers": {
    "roblox-mcp": {
      "command": "node",
      "args": [
        "C:\\Users\\YourName\\roblox-executor-mcp\\dist\\index.js",
        "--server-name",
        "roblox-mcp"
      ]
    }
  }
}
```

## 3. Restart Claude Desktop

Fully quit Claude Desktop (from the tray or menu bar, not just the window) and reopen it.

## Verify

Open the tools menu in the chat input. `roblox-mcp` should be listed with its tools. If it doesn't appear:

- Confirm `dist/index.js` exists (run `npm run build`)
- Check the path in the config
- Confirm Node.js 18 or newer is installed (`node -v`)
- Check the MCP logs in `~/Library/Logs/Claude/` (macOS) or `%APPDATA%\Claude\logs\` (Windows)
