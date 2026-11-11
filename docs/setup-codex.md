# Codex Setup

The harness installer configures Codex for you (`npm run install:harnesses`, then select **Codex**). It writes the same block shown below into `~/.codex/config.toml` and replaces an older `roblox-mcp` block if one exists.

Before setting it up by hand, build the server once from the repo root:

```bash
npm install
npm run build
```

## Option 1: Codex CLI command

```bash
codex mcp add roblox-mcp -- node /path/to/roblox-executor-mcp/dist/index.js --server-name roblox-mcp
```

## Option 2: Edit `config.toml`

Codex CLI, the IDE extension, and the desktop app share `~/.codex/config.toml` (`%USERPROFILE%\.codex\config.toml` on Windows). Add:

```toml
[mcp_servers.roblox-mcp]
command = "node"
args = ["/path/to/roblox-executor-mcp/dist/index.js", "--server-name", "roblox-mcp"]
```

Replace `/path/to/roblox-executor-mcp` with the absolute path where you cloned the repo. On Windows, use forward slashes, for example `C:/Users/you/roblox-executor-mcp/dist/index.js`.

## Restart and verify

Start a new Codex session, then run `/mcp` in the CLI. `roblox-mcp` should be listed with its tools. If it is missing:

- Confirm `dist/index.js` exists (run `npm run build`)
- Check the path in `config.toml`
- Confirm Node.js 18 or newer is installed (`node -v`)
