import assert from "node:assert/strict";
import test from "node:test";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { mkdtemp, writeFile, unlink, rmdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { buildLoaderSnippet } from "../src/shared/connector-snippet.mjs";

const run = promisify(execFile);
test("generated loaders work without getgenv or HttpGet and with request aliases", async () => {
  const dir = await mkdtemp(path.join(tmpdir(), "mcp-loader-test-"));
  const file = path.join(dir, "loader.luau");
  try {
    for (const [getgenv, alias] of [["nil", "http_request"], ['function() error("unsupported") end', "syn.request"], ["function() return false end", "http.request"]]) {
      const prefix = `local shared = {}
local _G = shared
local getgenv = ${getgenv}
local request, http_request
local syn, http = {}, {}
local downloads = 0
local function send(options)
    assert(options.Url == "http://127.0.0.1:16384/script.luau")
    downloads += 1
    return {status = 200, body = "connector source"}
end
${alias} = send
local game = { HttpGet = function() error("unsupported") end }
local loadstring = function(source)
    assert(source == "connector source")
    return function() shared.MCP_Loaded = true end
end
local task = { wait = function() assert(shared.MCP_Loaded) end }
local warn = function(message) error(message) end
`;
      await writeFile(file, prefix + buildLoaderSnippet("127.0.0.1:16384") + '\nassert(shared.MCP_Loaded and downloads == 1)\nprint("loader fixture passed")\n');
      const { stdout } = await run("luau", [file]);
      assert.match(stdout, /loader fixture passed/);
    }
  } finally { await unlink(file); await rmdir(dir); }
});
