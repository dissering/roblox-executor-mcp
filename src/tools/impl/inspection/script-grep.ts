import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { clientStampPrefix, toolTextResponse, type ToolTextResponse } from "../../factory.js";
import { isSecondaryRelay, relayToolToApi } from "../../factory.js";
import { maxOutputCharsSchema } from "../../schemas.js";
import { fetchScriptSearchIndex, type ScriptSearchDocument } from "./script-sources.js";

interface ScriptMatch {
  script: ScriptSearchDocument;
  blocks: string[];
}

interface SearchOptions {
  query: string;
  limit: number;
  contextLines: number;
  maxMatchesPerScript: number;
  maxResults?: number;
  literal: boolean;
  caseSensitive: boolean;
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function compileQuery(query: string, literal: boolean, caseSensitive: boolean): RegExp {
  return new RegExp(literal ? escapeRegExp(query) : query, caseSensitive ? "" : "i");
}

/** Clamp an integer into [min, max] with a fallback for non-finite input. */
function clampInt(value: number, fallback: number, min: number, max: number): number {
  if (!Number.isFinite(value)) return fallback;
  return Math.min(max, Math.max(min, Math.floor(value)));
}

function getLineBlock(lines: string[], lineIndex: number, contextLines: number): string {
  const block: string[] = [];
  const start = Math.max(0, lineIndex - contextLines);
  const end = Math.min(lines.length - 1, lineIndex + contextLines);

  for (let i = start; i <= end; i += 1) {
    const marker = i === lineIndex ? ">" : " ";
    block.push(`${marker} ${i + 1}: ${lines[i] ?? ""}`);
  }

  return block.join("\n");
}

function searchScripts(
  scripts: ScriptSearchDocument[],
  regex: RegExp,
  options: SearchOptions
): { matches: ScriptMatch[]; totalMatches: number; limited: boolean } {
  // Clamp every numeric parameter so a single MCP call cannot flood context.
  // (Mirrors the hard caps the HTTP /api/tool relay already enforces.)
  const limit = clampInt(options.limit, 10, 1, 100);
  const contextLines = clampInt(options.contextLines, 1, 0, 10);
  const maxMatchesPerScript = clampInt(options.maxMatchesPerScript, 3, 1, 50);
  const maxResults =
    options.maxResults === undefined
      ? 30
      : clampInt(options.maxResults, 30, 1, 1000);

  const matches: ScriptMatch[] = [];
  let totalMatches = 0;
  let limited = false;

  for (const script of scripts) {
    if (matches.length >= limit) {
      limited = true;
      break;
    }

    if (maxResults !== undefined && totalMatches >= maxResults) {
      limited = true;
      break;
    }

    const effectiveCap =
      maxResults === undefined
        ? maxMatchesPerScript
        : Math.min(maxMatchesPerScript, maxResults - totalMatches);

    if (effectiveCap <= 0) {
      limited = true;
      break;
    }

    const lines = script.source.split(/\r?\n/);
    const blocks: string[] = [];

    for (let lineIndex = 0; lineIndex < lines.length; lineIndex += 1) {
      if (blocks.length >= effectiveCap) break;

      const line = lines[lineIndex] ?? "";
      if (!regex.test(line)) continue;

      blocks.push(getLineBlock(lines, lineIndex, contextLines));
    }

    if (blocks.length === 0) continue;

    totalMatches += blocks.length;
    matches.push({ script, blocks });
  }

  return { matches, totalMatches, limited };
}

function formatResults(
  totalMatches: number,
  matches: ScriptMatch[],
  limited: boolean,
  syncNote: string
): string {
  const header =
    `${totalMatches} total ${totalMatches === 1 ? "match" : "matches"} across ` +
    `${matches.length}${matches.length === 1 ? " script" : " scripts"}` +
    (limited ? " (results limited)" : "") +
    syncNote;

  if (matches.length === 0) return header;

  const body = matches.map(({ script, blocks }) => {
    const scriptPath = script.path || `<ScriptProxy: ${script.debugId}>`;
    const matchCount = blocks.length;
    return (
      `[${scriptPath}] ${matchCount}${matchCount === 1 ? " match" : " matches"}\n\n` +
      blocks.join("\n\n")
    );
  });

  return header + "\n\n" + body.join("\n\n---\n\n");
}

export default function register(server: McpServer): void {
  server.registerTool(
    "script-grep",
    {
      title: "Grep across all scripts in the game",
      description:
        "Search decompiled Roblox scripts with JavaScript regex or literal string matching. Use for exact identifiers or code patterns; use semantic-search-scripts when behavior is known but names are not.",
      inputSchema: z.object({
        query: z
          .string()
          .describe(
            "Search pattern (JavaScript RegExp syntax). Set literal=true for an exact string match."
          ),
        limit: z
          .number()
          .describe("Maximum number of scripts to return results from (default: 10)")
          .optional()
          .default(10),
        contextLines: z
          .number()
          .describe("Number of lines of context to show before and after each match (default: 1)")
          .optional()
          .default(1),
        maxMatchesPerScript: z
          .number()
          .describe("Maximum number of matches to return per script (default: 3)")
          .optional()
          .default(3),
        maxResults: z
          .number()
          .describe(
            "Maximum total number of matches across ALL scripts (default: 30). Use this to cap total matches, e.g. maxResults=1 to find just the first match."
          )
          .optional()
          .default(30),
        literal: z
          .boolean()
          .describe(
            "When true, treats the query as a plain literal string - no regex interpretation. Equivalent to grep -F / ripgrep -F. (default: false)"
          )
          .optional()
          .default(false),
        caseSensitive: z
          .boolean()
          .describe("When false, matches case-insensitively. Equivalent to grep -i. (default: true)")
          .optional()
          .default(true),
        maxOutputChars: maxOutputCharsSchema,
      }),
    },
    async (options): Promise<ToolTextResponse> => {
      // Secondary mode: script sources live on the primary, relay the request.
      if (isSecondaryRelay()) {
        return relayToolToApi("script-grep", {
          query: options.query,
          limit: options.limit,
          contextLines: options.contextLines,
          maxMatchesPerScript: options.maxMatchesPerScript,
          maxResults: options.maxResults,
          literal: options.literal,
          caseSensitive: options.caseSensitive,
          maxOutputChars: options.maxOutputChars,
        }, 60000, {
          maxOutputChars: options.maxOutputChars,
          truncationHint: "Rerun script-grep with a narrower query, lower limit, or lower maxResults.",
        });
      }

      let regex: RegExp;
      try {
        regex = compileQuery(options.query, options.literal, options.caseSensitive);
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        return toolTextResponse(`Invalid regex pattern: ${message}`, {}, true);
      }

      const indexResult = await fetchScriptSearchIndex({ allowIncomplete: true, startMapping: true });
      if (!indexResult.ok) return indexResult.response;

      const { matches, totalMatches, limited } = searchScripts(
        indexResult.index.scripts,
        regex,
        options
      );

      const index = indexResult.index;
      const syncNote = index.hasFinishedMapping
        ? ""
        : ` (partial index: ${index.mappedSources}/${index.sourcesToMap} scripts uploaded)`;

      return toolTextResponse(
        clientStampPrefix() + formatResults(totalMatches, matches, limited, syncNote),
        {
          maxOutputChars: options.maxOutputChars,
          truncationHint: "Rerun script-grep with a narrower query, lower limit, or lower maxResults.",
        }
      );
    }
  );
}
