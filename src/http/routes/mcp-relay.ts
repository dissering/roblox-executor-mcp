import crypto from "crypto";
import { WebSocket } from "ws";
import {
  GetResponseOfIdFromClient,
  httpResponseResolvers,
  relayClients,
  relayRequestOrigin,
  SendToClient,
} from "../../bridge/handlers/shared/communication.js";
import {
  formatActiveClientListForTool,
  resolveTargetClient,
  setActiveClientId,
} from "../../bridge/handlers/shared/registry.js";

interface RelayMessage {
  id?: string;
  type?: string;
  targetClientId?: string;
  [key: string]: unknown;
}

const RELAY_RESPONSE_TIMEOUT_MS = 120_000;

function sendIfOpen(ws: WebSocket, payload: unknown): void {
  if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(payload));
}

function failPendingRequestsFrom(ws: WebSocket, reason: string): void {
  for (const [transportId, origin] of [...relayRequestOrigin]) {
    if (origin !== ws) continue;
    relayRequestOrigin.delete(transportId);
    httpResponseResolvers.get(transportId)?.({ id: transportId, output: undefined, error: reason });
  }
}

export function WS(ws: WebSocket): void {
  console.error(`[Primary] Relay client connected. Total: ${relayClients.size + 1}`);
  relayClients.add(ws);

  ws.on("message", (rawData) => {
    try {
      const message: RelayMessage = JSON.parse(rawData.toString());

      // Relay-level request handled directly by the primary.
      if (message.type === "list-clients" && message.id) {
        ws.send(
          JSON.stringify({
            id: message.id,
            output: formatActiveClientListForTool(),
          })
        );
        return;
      }

      if (message.type === "set-active-client" && message.id) {
        const requestedClientId =
          typeof message.targetClientId === "string" ? message.targetClientId : "";
        const target = resolveTargetClient(requestedClientId);
        if (!target) {
          ws.send(
            JSON.stringify({
              id: message.id,
              output: undefined,
              error: `Invalid or inactive client ID: ${requestedClientId}. Use list-clients to get active client IDs.`,
            })
          );
          return;
        }

        setActiveClientId(target.clientId);
        ws.send(
          JSON.stringify({
            id: message.id,
            output:
              `Active client set to ${target.clientId} ` +
              `(${target.username} @ ${target.placeName}, ${target.transport}).`,
            clientId: target.clientId,
          })
        );
        return;
      }

      const targetClientId = message.targetClientId;
      if (targetClientId) {
        delete message.targetClientId;
      }

      const target = resolveTargetClient(targetClientId);
      if (target) {
        const originalId = message.id;
        if (!originalId) {
          SendToClient(target, JSON.stringify(message));
          return;
        }

        // Relay clients pick their own IDs, so two of them can collide with each
        // other or with a local primary request. Route under a fresh transport ID
        // and restore the original ID on the way back.
        const transportId = `relay:${crypto.randomUUID()}`;
        relayRequestOrigin.set(transportId, ws);
        void GetResponseOfIdFromClient(transportId, RELAY_RESPONSE_TIMEOUT_MS).then((response) => {
          relayRequestOrigin.delete(transportId);
          sendIfOpen(ws, { ...response, id: originalId });
        });
        SendToClient(target, JSON.stringify({ ...message, id: transportId }));
      } else if (message.id) {
        ws.send(
          JSON.stringify({
            id: message.id,
            output: undefined,
            error: "No active Roblox client connected.",
          })
        );
      }
    } catch (e) {
      console.error("[Primary] Error parsing relay message:", e);
    }
  });

  ws.on("close", () => {
    relayClients.delete(ws);
    console.error(`[Primary] Relay client disconnected. Total: ${relayClients.size}`);
    failPendingRequestsFrom(ws, "Relay client disconnected.");
  });

  ws.on("error", (err) => {
    console.error("[Primary] Relay client error:", err.message);
    relayClients.delete(ws);
    failPendingRequestsFrom(ws, `Relay client error: ${err.message}`);
  });
}
