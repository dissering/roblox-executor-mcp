# Claude Code (CLI) Setup

The harness installer configures Claude Code for you (`npm run install:harnesses`, then select **Claude Code**). It runs `claude mcp add` with the same arguments shown below.

Before setting it up by hand, build the server once from the repo root:

```bash
npm install
npm run build
```

## 1. Add the MCP server

Available in every project (user scope):

```bash
claude mcp add --scope user roblox-mcp -- node /path/to/roblox-executor-mcp/dist/index.js --server-name roblox-mcp
```

Only in the current project, private to you (the default, local scope):

```bash
claude mcp add roblox-mcp -- node /path/to/roblox-executor-mcp/dist/index.js --server-name roblox-mcp
```

Replace `/path/to/roblox-executor-mcp` with the absolute path where you cloned the repo. Use `--scope project` instead to write a shared `.mcp.json` in the project root.

## 2. Verify

Start Claude Code and run:

```
/mcp
```

`roblox-mcp` should show as `connected`. If it shows `failed`:

- Confirm `dist/index.js` exists (run `npm run build`)
- Check the path you passed to `claude mcp add`
- Confirm Node.js 18 or newer is installed (`node -v`)

## Managing the server

```bash
# List configured MCP servers
claude mcp list

# Remove the server (add --scope user if you added it there)
claude mcp remove roblox-mcp
```
