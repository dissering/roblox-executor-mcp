import crypto from "crypto";
import { WebSocket } from "ws";
import { TOOL_RESPONSE_TIMEOUT } from "../../../config.js";
import type {
  DispatchResult,
  InstanceRole,
  RobloxClient,
  RobloxResponse,
  ResponseResolver,
} from "../../types.js";
import { getActiveClients, resolveTargetClient } from "./registry.js";

const MAX_PENDING_HTTP_COMMANDS = 100;

// ─── Instance role ────────────────────────────────────────────────────────────
let instanceRole: InstanceRole = "primary";

export function getInstanceRole(): InstanceRole {
  return instanceRole;
}

export function setInstanceRole(role: InstanceRole): void {
  instanceRole = role;
}

// ─── Primary-mode routing state ───────────────────────────────────────────────
export const httpResponseResolvers: Map<string, ResponseResolver> = new Map();

export const relayClients: Set<WebSocket> = new Set();
export const relayRequestOrigin: Map<string, WebSocket> = new Map();

// ─── Secondary-mode routing state ─────────────────────────────────────────────
let relaySocket: WebSocket | null = null;
export const secondaryResponseResolvers: Map<string, ResponseResolver> = new Map();

export function getRelaySocket(): WebSocket | null {
  return relaySocket;
}

export function setRelaySocket(ws: WebSocket | null): void {
  relaySocket = ws;
}

export function resetPrimaryState(): void {
  for (const [id, resolver] of httpResponseResolvers) {
    resolver({ id, error: "Primary connection reset." });
  }
  httpResponseResolvers.clear();
  relayClients.clear();
  relayRequestOrigin.clear();
}

export function resetSecondaryState(): void {
  for (const [id, resolver] of secondaryResponseResolvers) {
    resolver({ id, error: "Secondary connection reset." });
  }
  secondaryResponseResolvers.clear();
}

// ─── Low-level send ───────────────────────────────────────────────────────────
export function SendToClient(target: RobloxClient, message: string): void {
  if (target.transport === "ws" && target.ws && target.ws.readyState === WebSocket.OPEN) {
    target.ws.send(message);
  } else if (target.transport === "http") {
    if (target.pendingHttpCommands.length >= MAX_PENDING_HTTP_COMMANDS) {
      target.pendingHttpCommands.shift();
    }
    target.pendingHttpCommands.push(message);

    const waiter = target.pendingPollResolve;
    if (waiter) {
      target.pendingPollResolve = null;
      const batch = target.pendingHttpCommands;
      target.pendingHttpCommands = [];
      waiter(batch);
    }
  }
}

// ─── Response waiter ──────────────────────────────────────────────────────────
export function GetResponseOfIdFromClient(
  id: string,
  timeoutMs: number = TOOL_RESPONSE_TIMEOUT
): Promise<RobloxResponse> {
  const resolvers = instanceRole === "secondary" ? secondaryResponseResolvers : httpResponseResolvers;
  return new Promise((resolve) => {
    let settled = false;
    let timeout: NodeJS.Timeout;

    const resolveOnce: ResponseResolver = (data) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      if (resolvers.get(id) === resolveOnce) resolvers.delete(id);
      resolve(data);
    };

    timeout = setTimeout(() => {
      resolveOnce({
        id,
        output: undefined,
        error: `Timed out waiting for response after ${timeoutMs}ms.`,
      });
    }, timeoutMs);

    resolvers.set(id, resolveOnce);
  });
}

// ─── High-level dispatch ──────────────────────────────────────────────────────
export function SendArbitraryDataToClient(
  type: string,
  data: Record<string, unknown>,
  id?: string,
  clientId?: string
): DispatchResult {
  if (instanceRole === "secondary") {
    if (!relaySocket || relaySocket.readyState !== WebSocket.OPEN) return null;
    const requestId = id ?? crypto.randomUUID();
    const message = {
      id: requestId,
      ...data,
      type,
      ...(clientId ? { targetClientId: clientId } : {}),
    };
    relaySocket.send(JSON.stringify(message));
    return requestId;
  }

  // Primary mode
  if (clientId !== undefined) {
    const target = resolveTargetClient(clientId);
    if (!target) return "INVALID_CLIENT";

    const requestId = id ?? crypto.randomUUID();
    const message = { id: requestId, ...data, type };
    SendToClient(target, JSON.stringify(message));
    return requestId;
  }

  // No clientId: broadcast to all active clients.
  const activeClients = getActiveClients();
  if (activeClients.length === 0) return null;

  const requestId = id ?? crypto.randomUUID();
  const message = { id: requestId, ...data, type };

  for (const target of activeClients) {
    SendToClient(target, JSON.stringify(message));
  }

  return requestId;
}

// ─── Route a response from a Roblox client ────────────────────────────────────
export function handleRobloxResponse(data: RobloxResponse): void {
  if (!data.id) return;

  const resolver = httpResponseResolvers.get(data.id);
  if (resolver) {
    resolver(data);
  }
}
