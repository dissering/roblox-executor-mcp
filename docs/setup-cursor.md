# Cursor Setup

The harness installer configures Cursor for you (`npm run install:harnesses`, then select **Cursor**). Use the options below to set it up by hand.

Before any manual option, build the server once from the repo root:

```bash
npm install
npm run build
```

## Option 1: Deeplink

Click the button, then edit the path in Cursor's MCP settings to point at your checkout:

[![Install MCP Server](https://cursor.com/deeplink/mcp-install-dark.svg)](https://cursor.com/en-US/install-mcp?name=roblox-mcp&config=eyJjb21tYW5kIjoibm9kZSIsImFyZ3MiOlsiL3BhdGgvdG8vcm9ibG94LWV4ZWN1dG9yLW1jcC9kaXN0L2luZGV4LmpzIiwiLS1zZXJ2ZXItbmFtZSIsInJvYmxveC1tY3AiXX0=)

## Option 2: JSON config

Add this to `~/.cursor/mcp.json` (global) or `.cursor/mcp.json` in a project:

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

Replace `/path/to/roblox-executor-mcp` with the absolute path where you cloned the repo. On Windows, use forward slashes or escaped backslashes, for example `C:/Users/you/roblox-executor-mcp/dist/index.js`.

## Verify

Open **Cursor Settings → MCP**. `roblox-mcp` should show a green status. If it shows red:

- Confirm `dist/index.js` exists (run `npm run build`)
- Check the path in the config
- Confirm Node.js 18 or newer is installed (`node -v`)
