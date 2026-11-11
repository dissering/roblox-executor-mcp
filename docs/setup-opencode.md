# OpenCode Setup

OpenCode reads MCP servers from the `mcp` key of its global config at `~/.config/opencode/opencode.json` (or `$XDG_CONFIG_HOME/opencode/opencode.json`). The same path is used on Windows: `%USERPROFILE%\.config\opencode\opencode.json`.

## Installer

OpenCode is in the recommended list. Run the installer and select **OpenCode**:

```bash
npm run install:harnesses
```

The installer picks the config file in this order:

1. The file named by the `OPENCODE_CONFIG` environment variable, if set.
2. `opencode.jsonc`, if it exists and `opencode.json` does not.
3. `opencode.json`.

It preserves unrelated keys and MCP servers and writes a `.bak` copy before changing an existing file. Comments in a `.jsonc` file are not kept, so check the `.bak` copy if you rely on them.

## Manual configuration

Add this to your OpenCode config:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "roblox-mcp": {
      "type": "local",
      "command": [
        "node",
        "/absolute/path/to/roblox-executor-mcp/dist/index.js",
        "--server-name",
        "roblox-mcp"
      ],
      "enabled": true,
      "timeout": 30000
    }
  }
}
```

`timeout` is how long OpenCode waits for the server to list its tools, in milliseconds. The default of 5000 can be too short on a cold start, which makes the server show as failed.

On Windows, use forward slashes or escaped backslashes in the path, for example `C:/Users/you/roblox-executor-mcp/dist/index.js`.

## Verify in OpenCode

1. Restart OpenCode.
2. Run `opencode mcp list` and confirm `roblox-mcp` is listed as connected.
3. Run the Roblox loader printed by the installer in your executor.
4. Ask OpenCode to call `list-clients` to confirm the game client is attached.

See OpenCode's [MCP server documentation](https://opencode.ai/docs/mcp-servers/) for per-project configuration and tool filtering.
