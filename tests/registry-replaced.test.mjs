import assert from "node:assert/strict";
import test from "node:test";

import { registerClient, resetRegistry } from "../dist/bridge/handlers/shared/registry.js";

function fakeSocket() {
  return {
    readyState: 1,
    sent: [],
    closed: false,
    send(message) { this.sent.push(JSON.parse(message)); },
    close() { this.closed = true; },
  };
}

const info = { username: "fixture", userId: 1, placeId: 1, jobId: "job", placeName: "place", sessionId: "same-session" };

test("a second connector for the same session tells the first one it was replaced", (t) => {
  t.after(() => resetRegistry());
  const first = fakeSocket();
  const second = fakeSocket();

  const firstId = registerClient({ ...info, transport: "ws", ws: first });
  const secondId = registerClient({ ...info, transport: "ws", ws: second });

  assert.equal(secondId, firstId, "the session keeps its client id");
  assert.equal(first.sent.at(-1)?.type, "replaced", "the old socket is told it was replaced");
  assert.equal(first.closed, true, "the old socket is closed");
  assert.equal(second.sent.length, 0, "the new socket gets no replaced notice");
  assert.equal(second.closed, false);
});

test("re-registering on the same socket does not send a replaced notice", (t) => {
  t.after(() => resetRegistry());
  const socket = fakeSocket();
  registerClient({ ...info, transport: "ws", ws: socket });
  registerClient({ ...info, transport: "ws", ws: socket });
  assert.equal(socket.sent.length, 0);
  assert.equal(socket.closed, false);
});
