import crypto from "crypto";
import { WebSocket } from "ws";
import { HTTP_POLL_TIMEOUT } from "../../../config.js";
import type { RobloxClient } from "../../types.js";
import { clearScriptSourceIndex } from "./script-source-store.js";
import { clearDecompilerHealthForClient } from "../../../decompiler/health.js";

const clientRegistry: Map<string, RobloxClient> = new Map();
const wsToClientId: Map<WebSocket, string> = new Map();
const HTTP_CLIENT_RETENTION_MS = HTTP_POLL_TIMEOUT * 2;

let activeClientId: string | undefined = undefined;
let activeClientIsRemote = false;

function isClientActive(entry: RobloxClient): boolean {
  if (entry.transport === "ws") {
    return Boolean(entry.ws && entry.ws.readyState === WebSocket.OPEN);
  }
  return Date.now() - entry.lastHttpPoll < HTTP_POLL_TIMEOUT;
}

function removeClient(clientId: string, reason: string): void {
  const entry = clientRegistry.get(clientId);
  if (!entry) return;
  if (entry.ws) wsToClientId.delete(entry.ws);
  entry.pendingPollResolve?.([]);
  clientRegistry.delete(clientId);
  if (!activeClientIsRemote && activeClientId === clientId) activeClientId = undefined;
  clearScriptSourceIndex(clientId);
  clearDecompilerHealthForClient(clientId);
  console.error(`[Registry] Client ${reason}: ${clientId}`);
}

export function cleanupInactiveHttpClients(now = Date.now()): number {
  let removed = 0;
  for (const [clientId, entry] of clientRegistry) {
    if (entry.transport !== "http" || now - entry.lastHttpPoll < HTTP_CLIENT_RETENTION_MS) continue;
    removeClient(clientId, "expired");
    removed += 1;
  }
  return removed;
}

const cleanupTimer = setInterval(cleanupInactiveHttpClients, HTTP_POLL_TIMEOUT);
cleanupTimer.unref();

function findClientBySessionId(sessionId: string): RobloxClient | undefined {
  for (const entry of clientRegistry.values()) {
    if (entry.sessionId === sessionId) return entry;
  }
  return undefined;
}

function findUniqueClientByIdOrPrefix(clientId: string): RobloxClient | undefined {
  const normalized = clientId.trim();
  if (!normalized) return undefined;

  const exact = clientRegistry.get(normalized);
  if (exact) return exact;

  const matches = getActiveClients().filter((entry) => entry.clientId.startsWith(normalized));
  return matches.length === 1 ? matches[0] : undefined;
}

export function getActiveClientId(): string | undefined {
  if (!activeClientId) return undefined;
  if (activeClientIsRemote) return activeClientId;
  const active = clientRegistry.get(activeClientId);
  if (!active || !isClientActive(active)) {
    activeClientId = undefined;
    activeClientIsRemote = false;
    return undefined;
  }
  return activeClientId;
}

export function setActiveClientId(clientId: string, options: { remote?: boolean } = {}): void {
  activeClientId = clientId;
  activeClientIsRemote = options.remote === true;
}

export function resetRegistry(): void {
  for (const clientId of [...clientRegistry.keys()]) removeClient(clientId, "reset");
  wsToClientId.clear();
  activeClientId = undefined;
  activeClientIsRemote = false;
}

export function registerClient(info: {
  username: string;
  userId: number;
  placeId: number;
  jobId: string;
  placeName: string;
  sessionId?: string;
  transport: "ws" | "http";
  ws?: WebSocket;
}): string {
  const existing = info.sessionId ? findClientBySessionId(info.sessionId) : undefined;
  if (existing) {
    // Two connectors in one Roblox session share a session id. Tell the older one it was
    // replaced so it stops, instead of reconnecting and kicking the newer one off in a loop.
    const replacedNotice = JSON.stringify({ type: "replaced", reason: "Another connector registered for this Roblox session." });
    if (existing.ws && existing.ws !== info.ws) {
      wsToClientId.delete(existing.ws);
      try {
        existing.ws.send(replacedNotice);
        existing.ws.close();
      } catch {
        // Best effort cleanup; the new transport below is authoritative.
      }
    }

    existing.pendingPollResolve?.(existing.transport === "http" && info.transport === "ws" ? [replacedNotice] : []);
    existing.username = info.username;
    existing.userId = info.userId;
    existing.placeId = info.placeId;
    existing.jobId = info.jobId;
    existing.placeName = info.placeName;
    existing.sessionId = info.sessionId;
    existing.transport = info.transport;
    existing.ws = info.ws;
    existing.lastHttpPoll = Date.now();
    existing.pendingPollResolve = null;

    if (info.ws) {
      wsToClientId.set(info.ws, existing.clientId);
    }

    console.error(
      `[Registry] Client refreshed: ${existing.clientId} (${info.username} @ ${info.placeName}, ${info.transport})`
    );
    return existing.clientId;
  }

  const clientId = crypto.randomUUID();
  const entry: RobloxClient = {
    clientId,
    sessionId: info.sessionId,
    username: info.username,
    userId: info.userId,
    placeId: info.placeId,
    jobId: info.jobId,
    placeName: info.placeName,
    transport: info.transport,
    ws: info.ws,
    lastHttpPoll: Date.now(),
    pendingHttpCommands: [],
    pendingPollResolve: null,
  };
  clientRegistry.set(clientId, entry);
  if (info.ws) {
    wsToClientId.set(info.ws, clientId);
  }
  console.error(
    `[Registry] Client registered: ${clientId} (${info.username} @ ${info.placeName}, ${info.transport})`
  );
  return clientId;
}

export function unregisterClient(clientId: string): void {
  removeClient(clientId, "unregistered");
}

export function getClientById(clientId: string): RobloxClient | undefined {
  return clientRegistry.get(clientId);
}

export function getClientIdByWs(ws: WebSocket): string | undefined {
  return wsToClientId.get(ws);
}

export function getActiveClients(): RobloxClient[] {
  const active: RobloxClient[] = [];
  for (const entry of clientRegistry.values()) {
    if (isClientActive(entry)) {
      active.push(entry);
    }
  }
  return active;
}

export function formatActiveClientListForTool(): string {
  const active = getActiveClients();
  if (active.length === 0) {
    return "No Roblox clients are currently connected.";
  }

  // Compact one-line-per-client format to minimize tokens vs pretty JSON.
  const selectedClientId = getActiveClientId();

  return active
    .map((c) => {
      const marker = c.clientId === selectedClientId ? "* " : "  ";
      return (
        `${marker}${c.clientId} | ${c.username ?? "?"} @ ${c.placeName ?? c.placeId} ` +
        `(place=${c.placeId} job=${c.jobId} ${c.transport})`
      );
    })
    .join("\n");
}

export function resolveTargetClient(clientId?: string): RobloxClient | null {
  if (clientId) {
    const entry = findUniqueClientByIdOrPrefix(clientId);
    if (!entry) return null;
    if (!isClientActive(entry)) return null;
    return entry;
  }

  const active = getActiveClients();
  if (active.length === 0) return null;

  const wsCl = active.filter((c) => c.transport === "ws");
  if (wsCl.length > 0) return wsCl[wsCl.length - 1]!;
  return active.sort((a, b) => b.lastHttpPoll - a.lastHttpPoll)[0]!;
}
