import {
  getActiveClientId,
  resolveTargetClient,
} from "../../../bridge/handlers/shared/registry.js";
import {
  getScriptSourceIndex,
  type ScriptSourceIndex,
  type StoredScriptSource,
} from "../../../bridge/handlers/shared/script-source-store.js";
import { toolTextResponse, type ToolTextResponse } from "../../factory.js";
import { SendArbitraryDataToClient } from "../../../bridge/handlers/shared/communication.js";
import { INVALID_CLIENT_ERROR, NO_CLIENT_ERROR } from "../../errors.js";

export type ScriptSearchDocument = StoredScriptSource;
export type ScriptSearchIndex = ScriptSourceIndex;

export type ScriptSearchIndexResult =
  | { ok: true; index: ScriptSearchIndex }
  | { ok: false; response: ToolTextResponse };

export function fetchScriptSearchIndex(
  options: { allowIncomplete?: boolean; startMapping?: boolean } = {}
): ScriptSearchIndexResult {
  const selectedClientId = getActiveClientId();
  const target = resolveTargetClient(selectedClientId);

  if (!target) {
    return {
      ok: false,
      response: selectedClientId ? INVALID_CLIENT_ERROR : NO_CLIENT_ERROR,
    };
  }

  const index = getScriptSourceIndex({
    clientId: target.clientId,
    placeId: target.placeId,
    jobId: target.jobId,
  });

  // Script mapping is off at connect. Search tools start it the first time they need it,
  // and the connector keeps it running for the rest of the session.
  const notStarted = index.mappingDisabled || (index.scripts.length === 0 && index.sourcesToMap === 0);
  if (options.startMapping && notStarted) {
    const requestId = SendArbitraryDataToClient("start-script-mapping", {}, undefined, target.clientId);
    if (requestId && requestId !== "INVALID_CLIENT") {
      return {
        ok: false,
        response: toolTextResponse(
          "Script indexing was off for this Roblox client, so it has started now in the background " +
            "(lightweight: a few decompile workers, paused during decompiler cooldowns). " +
            "Run this search again in a minute; results grow as scripts are indexed.",
          {},
          true
        ),
      };
    }
  }

  if (index.mappingDisabled && index.scripts.length === 0) {
    return {
      ok: false,
      response: toolTextResponse(
        "Script indexing is off for this Roblox client. Run script-grep or semantic-search-scripts to start it, " +
          "or set EnableScriptMapping = true in the loader settings.",
        {},
        true
      ),
    };
  }

  if (!options.allowIncomplete && !index.hasFinishedMapping) {
    return {
      ok: false,
      response: toolTextResponse(
        "The MCP server is still receiving script sources from the Roblox client " +
          `(${index.processedSources}/${index.sourcesToMap} processed, ${index.mappedSources} uploaded). Please try again later.`,
        {},
        true
      ),
    };
  }

  if (index.scripts.length === 0) {
    return {
      ok: false,
      response: toolTextResponse(
        `No script sources have been received from the Roblox client yet (${index.processedSources}/${index.sourcesToMap} processed). Indexing is running; try again shortly.`,
        {},
        true
      ),
    };
  }

  return { ok: true, index };
}
