import assert from "node:assert/strict";
import test from "node:test";

import { fetchScriptSearchIndex } from "../dist/tools/impl/inspection/script-sources.js";
import { upsertScriptSources } from "../dist/bridge/handlers/shared/script-source-store.js";
import { registerClient, resetRegistry, setActiveClientId, getClientById } from "../dist/bridge/handlers/shared/registry.js";
import { resetPrimaryState } from "../dist/bridge/handlers/shared/communication.js";

function connect(t, jobId) {
  const sent = [];
  const ws = { readyState: 1, close() {}, send: (message) => sent.push(JSON.parse(message)) };
  const clientId = registerClient({
    username: "fixture", userId: 1, placeId: 7, jobId, placeName: "place", transport: "ws", ws,
  });
  setActiveClientId(clientId);
  t.after(() => { resetRegistry(); resetPrimaryState(); });
  const client = getClientById(clientId);
  return { sent, identity: { clientId, placeId: client.placeId, jobId: client.jobId } };
}

const text = (result) => result.response.content[0].text;

test("search tools start script mapping when the client reports it is off", (t) => {
  const { sent, identity } = connect(t, "job-off");
  upsertScriptSources(identity, { mappingDisabled: true, hasFinishedMapping: true, sourcesToMap: 0 });

  const result = fetchScriptSearchIndex({ allowIncomplete: true, startMapping: true });
  assert.equal(result.ok, false);
  assert.match(text(result), /started now in the background/);
  assert.equal(sent.at(-1)?.type, "start-script-mapping", "the client is asked to start mapping");
});

test("callers that do not start mapping get a clear message instead", (t) => {
  const { sent, identity } = connect(t, "job-off-2");
  upsertScriptSources(identity, { mappingDisabled: true, hasFinishedMapping: true, sourcesToMap: 0 });

  const result = fetchScriptSearchIndex({ allowIncomplete: true });
  assert.equal(result.ok, false);
  assert.match(text(result), /indexing is off/);
  assert.equal(sent.length, 0, "nothing is sent without startMapping");
});

test("a running index returns partial results without restarting mapping", (t) => {
  const { sent, identity } = connect(t, "job-running");
  upsertScriptSources(identity, {
    mappingDisabled: false,
    hasFinishedMapping: false,
    sourcesToMap: 10,
    processedSources: 1,
    scripts: [{ debugId: "a", path: "game.ReplicatedStorage.Mod", source: "return 1", scriptHash: "h1" }],
  });

  const result = fetchScriptSearchIndex({ allowIncomplete: true, startMapping: true });
  assert.equal(result.ok, true);
  assert.equal(result.index.scripts.length, 1);
  assert.equal(sent.length, 0, "mapping is not restarted while it runs");
});

test("relayed script-grep and semantic search start mapping too", async (t) => {
  const { POST: apiTool } = await import("../dist/http/routes/api/tool.js");
  const { Readable } = await import("node:stream");
  const { sent, identity } = connect(t, "job-relay");
  upsertScriptSources(identity, { mappingDisabled: true, hasFinishedMapping: true, sourcesToMap: 0 });

  for (const type of ["script-grep", "semantic-search"]) {
    sent.length = 0;
    const request = Readable.from([Buffer.from(JSON.stringify({ type, query: "FireServer", clientId: identity.clientId }))]);
    let body;
    await apiTool(request, { writeHead() {}, end(text) { body = JSON.parse(text); } });
    assert.match(body.error ?? "", /started now in the background/, `${type} reports that indexing started`);
    assert.equal(sent.at(-1)?.type, "start-script-mapping", `${type} asks the client to start mapping`);
  }
});
