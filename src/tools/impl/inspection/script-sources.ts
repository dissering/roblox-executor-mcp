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

const MAPPING_STARTED_MESSAGE =
  "Script indexing was off for this Roblox client, so it has started now in the background " +
  "(lightweight: a few decompile workers, paused during decompiler cooldowns). " +
  "Run this search again in a minute; results grow as scripts are indexed.";

const MAPPING_OFF_MESSAGE =
  "Script indexing is off for this Roblox client. Run script-grep or semantic-search-scripts to start it, " +
  "or set EnableScriptMapping = true in the loader settings.";

/**
 * Script mapping is off at connect. Search tools call this before searching: when the
 * client has not indexed anything yet it is asked to start, and a message is returned
 * for the caller to show instead of an empty result. Returns null when the search can run.
 */
export function startScriptMappingIfNeeded(
  clientId: string,
  index: Pick<ScriptSourceIndex, "mappingDisabled" | "scripts" | "sourcesToMap">,
  start = true
): string | null {
  const notStarted = index.mappingDisabled || (index.scripts.length === 0 && index.sourcesToMap === 0);
  if (!notStarted) return null;
  if (start) {
    const requestId = SendArbitraryDataToClient("start-script-mapping", {}, undefined, clientId);
    if (requestId && requestId !== "INVALID_CLIENT") return MAPPING_STARTED_MESSAGE;
  }
  return index.mappingDisabled && index.scripts.length === 0 ? MAPPING_OFF_MESSAGE : null;
}

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

  const mappingMessage = startScriptMappingIfNeeded(target.clientId, index, options.startMapping === true);
  if (mappingMessage) {
    return { ok: false, response: toolTextResponse(mappingMessage, {}, true) };
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
