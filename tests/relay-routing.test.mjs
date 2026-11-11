import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import test from "node:test";

import { WS as relayRoute } from "../dist/http/routes/mcp-relay.js";
import {
  GetResponseOfIdFromClient,
  handleRobloxResponse,
  httpResponseResolvers,
  relayRequestOrigin,
  resetPrimaryState,
} from "../dist/bridge/handlers/shared/communication.js";
import { registerClient, resetRegistry, setActiveClientId } from "../dist/bridge/handlers/shared/registry.js";

function fakeRelaySocket() {
  const socket = new EventEmitter();
  socket.readyState = 1;
  socket.sent = [];
  socket.send = (message) => socket.sent.push(JSON.parse(message));
  socket.request = (message) => socket.emit("message", Buffer.from(JSON.stringify(message)));
  return socket;
}

function fakeRobloxClient() {
  const received = [];
  const ws = { readyState: 1, close() {}, send: (message) => received.push(JSON.parse(message)) };
  const clientId = registerClient({ username: "fixture", userId: 1, placeId: 1, jobId: "relay", placeName: "relay", transport: "ws", ws });
  setActiveClientId(clientId);
  return received;
}

const tick = () => new Promise((resolve) => setImmediate(resolve));

test("relay requests with colliding IDs each get their own response", async (t) => {
  t.after(() => { resetRegistry(); resetPrimaryState(); });
  const received = fakeRobloxClient();
  const relayA = fakeRelaySocket();
  const relayB = fakeRelaySocket();
  relayRoute(relayA);
  relayRoute(relayB);

  relayA.request({ id: "shared", type: "execute", source: "return 'a'" });
  relayB.request({ id: "shared", type: "execute", source: "return 'b'" });

  assert.equal(received.length, 2);
  const [toA, toB] = received;
  assert.notEqual(toA.id, toB.id, "transport IDs must be unique");
  assert.notEqual(toA.id, "shared", "the relay client's ID must not reach Roblox");

  handleRobloxResponse({ id: toB.id, output: "b" });
  handleRobloxResponse({ id: toA.id, output: "a" });
  await tick();

  assert.deepEqual(relayA.sent, [{ id: "shared", output: "a" }]);
  assert.deepEqual(relayB.sent, [{ id: "shared", output: "b" }]);
  assert.equal(relayRequestOrigin.size, 0);
  assert.equal(httpResponseResolvers.size, 0);
});

test("relay IDs cannot hijack a local primary request", async (t) => {
  t.after(() => { resetRegistry(); resetPrimaryState(); });
  const received = fakeRobloxClient();
  const relay = fakeRelaySocket();
  relayRoute(relay);

  const local = GetResponseOfIdFromClient("local-1", 1000);
  relay.request({ id: "local-1", type: "execute", source: "return 1" });
  const relayed = received.at(-1);

  handleRobloxResponse({ id: "local-1", output: "local" });
  handleRobloxResponse({ id: relayed.id, output: "relay" });
  await tick();

  assert.equal((await local).output, "local");
  assert.deepEqual(relay.sent, [{ id: "local-1", output: "relay" }]);
});

test("pending relay requests fail fast when the relay client disconnects", async (t) => {
  t.after(() => { resetRegistry(); resetPrimaryState(); });
  fakeRobloxClient();
  const relay = fakeRelaySocket();
  relayRoute(relay);

  relay.request({ id: "x", type: "execute", source: "while true do end" });
  assert.equal(relayRequestOrigin.size, 1);
  relay.readyState = 3;
  relay.emit("close");
  await tick();

  assert.equal(relayRequestOrigin.size, 0);
  assert.equal(httpResponseResolvers.size, 0);
});

test("resetting primary state resolves waiters instead of leaving them hanging", async () => {
  const pending = GetResponseOfIdFromClient("dangling", 60_000);
  resetPrimaryState();
  const response = await pending;
  assert.match(response.error, /reset/i);
});
