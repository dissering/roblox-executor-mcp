# BLACKBOX AI Setup

BLACKBOX AI supports MCP servers through its VS Code extension, which stores them in its extension settings file:

- **Windows:** `%APPDATA%\Code\User\globalStorage\blackboxapp.blackboxagent\settings\blackbox_mcp_settings.json`
- **macOS:** `~/Library/Application Support/Code/User/globalStorage/blackboxapp.blackboxagent/settings/blackbox_mcp_settings.json`
- **Linux:** `~/.config/Code/User/globalStorage/blackboxapp.blackboxagent/settings/blackbox_mcp_settings.json`

## Installer

Run the installer, reveal all harnesses if BLACKBOX AI was not detected automatically, and select **BLACKBOX AI (VS Code)**:

```bash
npm run install:harnesses -- --show-all-harnesses
```

The installer merges the server into the file above, keeps your other MCP servers, and writes a `.bak` copy before changing an existing file.

## Manual setup

Build the server once from the repo root:

```bash
npm install
npm run build
```

Then either open **MCP Servers** from the BLACKBOX AI panel and add a custom `stdio` server, or merge this into the settings file:

```json
{
  "mcpServers": {
    "roblox-mcp": {
      "command": "node",
      "args": [
        "/absolute/path/to/roblox-executor-mcp/dist/index.js",
        "--server-name",
        "roblox-mcp"
      ]
    }
  }
}
```

If the UI asks for separate fields, use name `roblox-mcp`, command `node`, and the three `args` values in order.

## Verify

Reload the VS Code window and confirm `roblox-mcp` appears as connected in the BLACKBOX AI MCP server list. Then run the loader printed by the installer in your executor. The MCP server and the Roblox client must use the same bridge URL.

BLACKBOX AI's MCP features are described in its [Visual Studio Marketplace listing](https://marketplace.visualstudio.com/items?itemName=Blackboxapp.blackbox).
