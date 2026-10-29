import assert from "node:assert/strict";
import test from "node:test";
import { mkdtemp, writeFile, unlink, rmdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { Readable } from "node:stream";

import registerExecute from "../dist/tools/impl/execution/execute.js";
import registerExecuteFile from "../dist/tools/impl/execution/execute-file.js";
import registerGetData from "../dist/tools/impl/inspection/get-data-by-code.js";
import { POST as dashboardTool } from "../dist/http/routes/api/tool.js";
import { handleRobloxResponse, resetPrimaryState } from "../dist/bridge/handlers/shared/communication.js";
import { registerClient, resetRegistry, setActiveClientId } from "../dist/bridge/handlers/shared/registry.js";

test("MCP and dashboard execution send code verbatim with a separate identity request", async t => {
  const messages = [];
  const ws = {
    readyState: 1,
    close() {},
    send(message) {
      const command = JSON.parse(message);
      messages.push(command);
      if (command.type === "get-data-by-code") setImmediate(() => handleRobloxResponse({ id: command.id, output: "42" }));
    },
  };
  const clientId = registerClient({ username: "fixture", userId: 1, placeId: 1, jobId: "test", placeName: "test", transport: "ws", ws });
  setActiveClientId(clientId);
  t.after(() => { resetRegistry(); resetPrimaryState(); });
  const callbacks = new Map();
  const server = { registerTool: (name, _schema, handler) => callbacks.set(name, handler) };
  registerExecute(server);
  registerExecuteFile(server);
  registerGetData(server);
  const source = "-- no identity function exists in this executor\nreturn 42";
  await callbacks.get("execute")({ code: source, threadContext: 4 });
  await callbacks.get("get-data-by-code")({ code: source, threadContext: 3, timeout: 1000, maxOutputChars: 1000 });
  const dir = await mkdtemp(path.join(tmpdir(), "mcp-execution-test-"));
  const file = path.join(dir, "source.luau");
  try {
    await writeFile(file, source);
    await callbacks.get("execute-file")({ filePath: file, threadContext: 2 });
  } finally { await unlink(file); await rmdir(dir); }
  assert.deepEqual(messages.map(m => [m.source, m.threadContext]), [[source,4],[source,3],[source,2]]);

  for (const type of ["execute", "get-data-by-code"]) {
    const request = Readable.from([Buffer.from(JSON.stringify({ type, code: source, clientId }))]);
    let result;
    await dashboardTool(request, { writeHead() {}, end(body) { result = JSON.parse(body); } });
    assert.equal(result.error, undefined);
    assert.equal(messages.at(-1).source, source);
    assert.equal(messages.at(-1).threadContext, 8);
  }
});
