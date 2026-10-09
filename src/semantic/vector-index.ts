import type { ScriptSourceIndex, StoredScriptSource } from "../bridge/handlers/shared/script-source-store.js";
import {
  readPersistedEmbedding,
  writePersistedEmbeddings,
} from "./embedding-cache.js";
import {
  buildSemanticChunkTemplates,
  expandQueryTokens,
  SEMANTIC_DOCUMENT_VERSION,
  tokenizeForSearch,
} from "./code-enrichment.js";
import { embedTexts } from "./embeddings.js";
import type { SemanticSettings } from "./settings.js";
import { getSemanticProviderModel } from "./settings.js";

const CHUNKING_VERSION = SEMANTIC_DOCUMENT_VERSION;
const OPENAI_EMBEDDING_BATCH_SIZE = 64;
const OLLAMA_EMBEDDING_BATCH_SIZE = 8;
const RRF_K = 60;
const MAX_RESULTS_PER_SCRIPT = 2;
const RESULT_OVERLAP_THRESHOLD = 0.5;

export interface SemanticSearchResult {
  path: string;
  debugId: string;
  startLine: number;
  endLine: number;
  score: number;
  denseScore: number;
  lexicalScore: number;
  chunkType: string;
  label: string;
  summary: string;
  features: string[];
  snippet: string;
}

export interface SemanticSearchProgress {
  message: string;
  completed: number;
  total: number;
}

interface ScriptChunk {
  id: string;
  embeddingId: string;
  debugId: string;
  path: string;
  startLine: number;
  endLine: number;
  body: string;
  semanticText: string;
  lexicalText: string;
  chunkType: string;
  label: string;
  summary: string;
  features: string[];
}

interface SourceChunkTemplate {
  embeddingId: string;
  startLine: number;
  endLine: number;
  body: string;
  semanticText: string;
  lexicalText: string;
  chunkType: string;
  label: string;
  summary: string;
  features: string[];
}

interface SemanticVectorSession {
  vectors: Map<string, number[]>;
}

const vectorSessionsByKey: Map<string, SemanticVectorSession> = new Map();
let sourceChunkTemplates = new WeakMap<StoredScriptSource, SourceChunkTemplate[]>();
const inFlightEmbeddingsByKey: Map<string, Promise<number[]>> = new Map();

function sessionKey(index: ScriptSourceIndex, settings: SemanticSettings): string {
  return [
    index.clientId,
    index.placeId,
    index.jobId,
    settings.provider,
    getSemanticProviderModel(settings),
    CHUNKING_VERSION,
  ].join(":");
}

function chunkId(script: StoredScriptSource, startLine: number, endLine: number): string {
  return [script.debugId, script.sourceHash, startLine, endLine].join(":");
}

function chunkTemplatesForSource(script: StoredScriptSource): SourceChunkTemplate[] {
  const cached = sourceChunkTemplates.get(script);
  if (cached) return cached;

  const chunks = buildSemanticChunkTemplates(script);
  sourceChunkTemplates.set(script, chunks);
  return chunks;
}

function chunkScript(script: StoredScriptSource): ScriptChunk[] {
  return chunkTemplatesForSource(script).map((chunk) => ({
    id: chunkId(script, chunk.startLine, chunk.endLine),
    embeddingId: chunk.embeddingId,
    debugId: script.debugId,
    path: script.path,
    startLine: chunk.startLine,
    endLine: chunk.endLine,
    body: chunk.body,
    semanticText: chunk.semanticText,
    lexicalText: chunk.lexicalText,
    chunkType: chunk.chunkType,
    label: chunk.label,
    summary: chunk.summary,
    features: chunk.features,
  }));
}

function buildChunks(scripts: StoredScriptSource[]): ScriptChunk[] {
  return scripts.flatMap(chunkScript);
}

function getOrCreateSession(key: string): SemanticVectorSession {
  const session = vectorSessionsByKey.get(key) ?? { vectors: new Map<string, number[]>() };
  vectorSessionsByKey.set(key, session);
  return session;
}

function getEmbeddingBatchSize(settings: SemanticSettings): number {
  return settings.provider === "ollama" ? OLLAMA_EMBEDDING_BATCH_SIZE : OPENAI_EMBEDDING_BATCH_SIZE;
}

function persistentEmbeddingKey(settings: SemanticSettings, embeddingId: string): string {
  return JSON.stringify([
    settings.provider,
    settings.provider === "openai" ? settings.openaiBaseUrl : settings.ollamaBaseUrl,
    getSemanticProviderModel(settings),
    CHUNKING_VERSION,
    embeddingId,
  ]);
}

function uniqueChunksByEmbedding(chunks: ScriptChunk[]): ScriptChunk[] {
  return [...new Map(chunks.map((chunk) => [chunk.embeddingId, chunk])).values()];
}

function pruneStaleVectors(session: SemanticVectorSession, chunks: ScriptChunk[]): void {
  const currentEmbeddingIds = new Set(chunks.map((chunk) => chunk.embeddingId));
  for (const embeddingId of session.vectors.keys()) {
    if (!currentEmbeddingIds.has(embeddingId)) session.vectors.delete(embeddingId);
  }
}

function countEmbeddedChunkAliases(session: SemanticVectorSession, chunks: ScriptChunk[]): number {
  let embeddedChunks = 0;
  for (const chunk of chunks) {
    if (session.vectors.has(chunk.embeddingId)) embeddedChunks += 1;
  }
  return embeddedChunks;
}

export function getSemanticIndexStats(
  index: ScriptSourceIndex,
  settings: SemanticSettings
): {
  chunkCount: number;
  embeddedChunks: number;
  uniqueChunkCount: number;
  embeddedUniqueChunks: number;
} {
  const chunks = buildChunks(index.scripts);
  const key = sessionKey(index, settings);
  const session = vectorSessionsByKey.get(key);
  const uniqueChunks = uniqueChunksByEmbedding(chunks);

  if (!session) {
    return {
      chunkCount: chunks.length,
      embeddedChunks: 0,
      uniqueChunkCount: uniqueChunks.length,
      embeddedUniqueChunks: 0,
    };
  }

  pruneStaleVectors(session, chunks);
  const embeddedChunks = countEmbeddedChunkAliases(session, chunks);
  const embeddedUniqueChunks = uniqueChunks.filter((chunk) =>
    session.vectors.has(chunk.embeddingId)
  ).length;

  return {
    chunkCount: chunks.length,
    embeddedChunks,
    uniqueChunkCount: uniqueChunks.length,
    embeddedUniqueChunks,
  };
}

function cosineSimilarity(a: number[], b: number[]): number {
  if (a.length !== b.length) {
    throw new Error(`Embedding dimension mismatch (${a.length} vs ${b.length}).`);
  }

  let dot = 0;
  let aMagnitude = 0;
  let bMagnitude = 0;

  for (let i = 0; i < a.length; i += 1) {
    const av = a[i] ?? 0;
    const bv = b[i] ?? 0;
    dot += av * bv;
    aMagnitude += av * av;
    bMagnitude += bv * bv;
  }

  if (aMagnitude === 0 || bMagnitude === 0) return 0;
  return dot / (Math.sqrt(aMagnitude) * Math.sqrt(bMagnitude));
}

const SNIPPET_MAX_LINES = 12;

function formatSnippet(chunk: ScriptChunk, queryTokens: string[]): string {
  const lines = chunk.body.split("\n");
  const uniqueQueryTokens = [...new Set(queryTokens)];
  let bestIndex = 0;
  let bestScore = 0;

  lines.forEach((line, index) => {
    const lineTokens = new Set(tokenizeForSearch(line));
    let score = 0;
    for (const token of uniqueQueryTokens) {
      if (lineTokens.has(token)) score += 1;
    }
    if (score > bestScore) {
      bestScore = score;
      bestIndex = index;
    }
  });

  const startIndex =
    lines.length <= SNIPPET_MAX_LINES || bestScore === 0
      ? 0
      : Math.max(0, Math.min(bestIndex - Math.floor(SNIPPET_MAX_LINES / 2), lines.length - SNIPPET_MAX_LINES));
  const endIndex = Math.min(lines.length, startIndex + SNIPPET_MAX_LINES);
  const snippetLines = lines.slice(startIndex, endIndex).map((line, index) => {
    return `${chunk.startLine + startIndex + index}: ${line}`;
  });

  if (startIndex > 0) snippetLines.unshift("...");
  if (endIndex < lines.length) snippetLines.push("...");

  return snippetLines.join("\n");
}

interface LexicalDocument {
  chunk: ScriptChunk;
  tokenCounts: Map<string, number>;
  length: number;
}

function tokenCountsForText(text: string): Map<string, number> {
  const counts = new Map<string, number>();
  for (const token of tokenizeForSearch(text)) {
    counts.set(token, (counts.get(token) ?? 0) + 1);
  }
  return counts;
}

function scoreLexicalChunks(chunks: ScriptChunk[], queryTokens: string[]): Map<string, number> {
  const uniqueQueryTokens = [...new Set(queryTokens)];
  const scores = new Map<string, number>();
  if (chunks.length === 0 || uniqueQueryTokens.length === 0) return scores;

  const documents: LexicalDocument[] = chunks.map((chunk) => {
    const tokenCounts = tokenCountsForText(chunk.lexicalText);
    let length = 0;
    for (const count of tokenCounts.values()) length += count;
    return { chunk, tokenCounts, length };
  });
  const averageLength =
    documents.reduce((sum, doc) => sum + doc.length, 0) / Math.max(1, documents.length);
  const documentFrequency = new Map<string, number>();

  for (const token of uniqueQueryTokens) {
    let count = 0;
    for (const doc of documents) {
      if (doc.tokenCounts.has(token)) count += 1;
    }
    documentFrequency.set(token, count);
  }

  const k1 = 1.2;
  const b = 0.75;
  const n = documents.length;

  for (const doc of documents) {
    let score = 0;
    for (const token of uniqueQueryTokens) {
      const tf = doc.tokenCounts.get(token) ?? 0;
      if (tf === 0) continue;

      const df = documentFrequency.get(token) ?? 0;
      const idf = Math.log(1 + (n - df + 0.5) / (df + 0.5));
      const denominator = tf + k1 * (1 - b + b * (doc.length / Math.max(1, averageLength)));
      score += idf * ((tf * (k1 + 1)) / denominator);
    }

    if (score > 0) scores.set(doc.chunk.id, score);
  }

  return scores;
}

function ranksById(ids: string[]): Map<string, number> {
  const ranks = new Map<string, number>();
  ids.forEach((id, index) => ranks.set(id, index + 1));
  return ranks;
}

function overlapRatio(a: SemanticSearchResult, b: SemanticSearchResult): number {
  if (a.debugId !== b.debugId) return 0;
  const start = Math.max(a.startLine, b.startLine);
  const end = Math.min(a.endLine, b.endLine);
  if (end < start) return 0;
  const overlap = end - start + 1;
  const aLength = a.endLine - a.startLine + 1;
  const bLength = b.endLine - b.startLine + 1;
  return overlap / Math.max(1, Math.min(aLength, bLength));
}

function diversifyResults(results: SemanticSearchResult[], limit: number): SemanticSearchResult[] {
  const selected: SemanticSearchResult[] = [];
  const perScript = new Map<string, number>();

  for (const result of results) {
    const scriptCount = perScript.get(result.debugId) ?? 0;
    if (scriptCount >= MAX_RESULTS_PER_SCRIPT) continue;
    if (selected.some((existing) => overlapRatio(existing, result) >= RESULT_OVERLAP_THRESHOLD)) {
      continue;
    }

    selected.push(result);
    perScript.set(result.debugId, scriptCount + 1);
    if (selected.length >= limit) break;
  }

  return selected;
}

async function embedMissingChunks(
  session: SemanticVectorSession,
  sessionCacheKey: string,
  chunks: ScriptChunk[],
  settings: SemanticSettings,
  onProgress?: (progress: SemanticSearchProgress) => void
): Promise<void> {
  pruneStaleVectors(session, chunks);

  const uniqueChunks = uniqueChunksByEmbedding(chunks);
  let loadedFromDisk = 0;

  if (settings.saveEmbeddingsToDisk) {
    for (const chunk of uniqueChunks) {
      if (session.vectors.has(chunk.embeddingId)) continue;

      const embedding = await readPersistedEmbedding(
        persistentEmbeddingKey(settings, chunk.embeddingId)
      );
      if (!embedding) continue;

      session.vectors.set(chunk.embeddingId, embedding);
      loadedFromDisk += 1;
    }
  }

  const missing = uniqueChunks.filter((chunk) => !session.vectors.has(chunk.embeddingId));
  const waitingForExisting: Promise<void>[] = [];
  const toEmbed: ScriptChunk[] = [];

  for (const chunk of missing) {
    const inFlightKey = `${sessionCacheKey}\0${chunk.embeddingId}`;
    const inFlight = inFlightEmbeddingsByKey.get(inFlightKey);
    if (inFlight) {
      waitingForExisting.push(
        inFlight.then((embedding) => {
          session.vectors.set(chunk.embeddingId, embedding);
        })
      );
    } else {
      toEmbed.push(chunk);
    }
  }

  const alreadyEmbedded = countEmbeddedChunkAliases(session, chunks);

  onProgress?.({
    message:
      missing.length === 0
        ? `Using cached embeddings for ${chunks.length} chunks`
        : `Embedding ${toEmbed.length} unique chunks (${alreadyEmbedded} chunk hits cached, ${loadedFromDisk} loaded from disk, ${waitingForExisting.length} already running)`,
    completed: alreadyEmbedded,
    total: chunks.length,
  });

  const batchSize = getEmbeddingBatchSize(settings);
  for (let i = 0; i < toEmbed.length; i += batchSize) {
    const batch = toEmbed.slice(i, i + batchSize);
    const embeddingPromise = embedTexts(
      settings,
      batch.map((chunk) => chunk.semanticText)
    );

    for (let j = 0; j < batch.length; j += 1) {
      const chunk = batch[j]!;
      const chunkPromise = embeddingPromise.then((embeddings) => {
        const embedding = embeddings[j];
        if (!embedding) {
          throw new Error("Embedding provider returned fewer vectors than expected.");
        }
        return embedding;
      });
      chunkPromise.catch(() => undefined);
      inFlightEmbeddingsByKey.set(`${sessionCacheKey}\0${chunk.embeddingId}`, chunkPromise);
    }

    try {
      const embeddings = await embeddingPromise;
      for (let j = 0; j < batch.length; j += 1) {
        const chunk = batch[j]!;
        const embedding = embeddings[j];
        if (!embedding) continue;
        session.vectors.set(chunk.embeddingId, embedding);
      }

      if (settings.saveEmbeddingsToDisk) {
        await writePersistedEmbeddings(
          batch.flatMap((chunk, index) => {
            const embedding = embeddings[index];
            return embedding
              ? [{ key: persistentEmbeddingKey(settings, chunk.embeddingId), embedding }]
              : [];
          })
        ).catch((error) => {
          console.error(`[Semantic] Failed to save embedding cache: ${String(error)}`);
        });
      }
    } finally {
      for (const chunk of batch) {
        inFlightEmbeddingsByKey.delete(`${sessionCacheKey}\0${chunk.embeddingId}`);
      }
    }

    onProgress?.({
      message: `Embedded ${Math.min(i + batch.length, toEmbed.length)} of ${toEmbed.length} new unique chunks`,
      completed: countEmbeddedChunkAliases(session, chunks),
      total: chunks.length,
    });

    await new Promise((resolve) => setImmediate(resolve));
  }

  if (waitingForExisting.length > 0) {
    await Promise.all(waitingForExisting);
    onProgress?.({
      message: "Reused embeddings from another running index job",
      completed: countEmbeddedChunkAliases(session, chunks),
      total: chunks.length,
    });
  }
}

export interface SemanticSearchOutput {
  results: SemanticSearchResult[];
  chunkCount: number;
  embeddedChunks: number;
  sourceIndexComplete: boolean;
  isPartialIndex: boolean;
}

export async function semanticSearchScripts(
  index: ScriptSourceIndex,
  settings: SemanticSettings,
  query: string,
  limit: number,
  minScore?: number,
  onProgress?: (progress: SemanticSearchProgress) => void
): Promise<SemanticSearchOutput> {
  const chunks = buildChunks(index.scripts);
  onProgress?.({
    message: index.hasFinishedMapping
      ? `Prepared ${chunks.length} code chunks`
      : `Prepared ${chunks.length} code chunks while scripts are still syncing (${index.mappedSources}/${index.sourcesToMap})`,
    completed: 0,
    total: chunks.length,
  });

  const key = sessionKey(index, settings);
  const session = getOrCreateSession(key);

  // Load any persisted embeddings from disk without generating new ones
  if (settings.saveEmbeddingsToDisk) {
    const uniqueChunks = uniqueChunksByEmbedding(chunks);
    for (const chunk of uniqueChunks) {
      if (session.vectors.has(chunk.embeddingId)) continue;
      const embedding = await readPersistedEmbedding(
        persistentEmbeddingKey(settings, chunk.embeddingId)
      );
      if (embedding) session.vectors.set(chunk.embeddingId, embedding);
    }
  }

  // Check how many chunks already have embeddings
  const embeddedCount = countEmbeddedChunkAliases(session, chunks);
  const uniqueChunks = uniqueChunksByEmbedding(chunks);
  const embeddedUniqueCount = uniqueChunks.filter((c) => session.vectors.has(c.embeddingId)).length;
  const totalUniqueCount = uniqueChunks.length;
  const isFullyIndexed = embeddedUniqueCount >= totalUniqueCount;

  if (isFullyIndexed) {
    // Fully indexed — embed any remaining aliases and search
    await embedMissingChunks(session, key, chunks, settings, onProgress);
  } else if (embeddedCount > 0) {
    // Partially indexed — skip blocking embed, search from what we have
    onProgress?.({
      message: `Searching from ${embeddedCount}/${chunks.length} cached embeddings (index incomplete: ${embeddedUniqueCount}/${totalUniqueCount} unique chunks)`,
      completed: embeddedCount,
      total: chunks.length,
    });
  } else {
    // No embeddings at all — must embed everything
    await embedMissingChunks(session, key, chunks, settings, onProgress);
  }

  onProgress?.({
    message: "Embedding query",
    completed: chunks.length,
    total: chunks.length + 1,
  });

  const queryTokens = expandQueryTokens(query);
  const [queryEmbedding] = await embedTexts(settings, [`Roblox Luau code search query: ${query}`]);
  if (!queryEmbedding) throw new Error("Embedding provider returned no query vector.");

  onProgress?.({
    message: "Ranking chunks",
    completed: chunks.length + 1,
    total: chunks.length + 1,
  });

  const chunkById = new Map(chunks.map((chunk) => [chunk.id, chunk]));
  const denseScores = new Map<string, number>();
  const lexicalScores = scoreLexicalChunks(chunks, queryTokens);
  const finalEmbeddedCount = countEmbeddedChunkAliases(session, chunks);

  for (const chunk of chunks) {
    const embedding = session.vectors.get(chunk.embeddingId);
    if (!embedding) continue;

    denseScores.set(chunk.id, cosineSimilarity(queryEmbedding, embedding));
  }

  const denseRankedIds = [...denseScores.entries()]
    .sort((a, b) => b[1] - a[1])
    .map(([id]) => id);
  const lexicalRankedIds = [...lexicalScores.entries()]
    .sort((a, b) => b[1] - a[1])
    .map(([id]) => id);
  const denseRanks = ranksById(denseRankedIds);
  const lexicalRanks = ranksById(lexicalRankedIds);
  const candidateIds = new Set([...denseRankedIds, ...lexicalRankedIds]);
  const scored: SemanticSearchResult[] = [];

  for (const id of candidateIds) {
    const chunk = chunkById.get(id);
    if (!chunk) continue;

    const denseScore = denseScores.get(id) ?? 0;
    const lexicalScore = lexicalScores.get(id) ?? 0;
    if (minScore !== undefined && denseScore < minScore && lexicalScore <= 0) continue;

    const denseRank = denseRanks.get(id);
    const lexicalRank = lexicalRanks.get(id);
    const hybridScore =
      (denseRank === undefined ? 0 : 1 / (RRF_K + denseRank)) +
      (lexicalRank === undefined ? 0 : 1 / (RRF_K + lexicalRank));

    scored.push({
      path: chunk.path,
      debugId: chunk.debugId,
      startLine: chunk.startLine,
      endLine: chunk.endLine,
      score: hybridScore,
      denseScore,
      lexicalScore,
      chunkType: chunk.chunkType,
      label: chunk.label,
      summary: chunk.summary,
      features: chunk.features.slice(0, 12),
      snippet: formatSnippet(chunk, queryTokens),
    });
  }

  scored.sort((a, b) =>
    b.score - a.score ||
    b.denseScore - a.denseScore ||
    b.lexicalScore - a.lexicalScore
  );
  const sourceIndexComplete = index.sourceIndexComplete;
  return {
    results: diversifyResults(scored, Math.max(0, Math.floor(limit))),
    chunkCount: chunks.length,
    embeddedChunks: finalEmbeddedCount,
    sourceIndexComplete,
    isPartialIndex: finalEmbeddedCount < chunks.length || !sourceIndexComplete,
  };
}

export async function semanticIndexCodebase(
  index: ScriptSourceIndex,
  settings: SemanticSettings,
  onProgress?: (progress: SemanticSearchProgress) => void
): Promise<{
  chunkCount: number;
  embeddedChunks: number;
  sourceIndexComplete: boolean;
  isPartialIndex: boolean;
}> {
  const chunks = buildChunks(index.scripts);
  onProgress?.({
    message: index.hasFinishedMapping
      ? `Prepared ${chunks.length} code chunks`
      : `Prepared ${chunks.length} code chunks while scripts are still syncing (${index.mappedSources}/${index.sourcesToMap})`,
    completed: 0,
    total: chunks.length,
  });

  const key = sessionKey(index, settings);
  const session = getOrCreateSession(key);

  await embedMissingChunks(session, key, chunks, settings, onProgress);
  const stats = getSemanticIndexStats(index, settings);
  const sourceIndexComplete = index.sourceIndexComplete;
  return {
    chunkCount: stats.chunkCount,
    embeddedChunks: stats.embeddedChunks,
    sourceIndexComplete,
    isPartialIndex: stats.embeddedChunks < stats.chunkCount || !sourceIndexComplete,
  };
}

export function clearSemanticIndexForClient(clientId: string): void {
  for (const key of vectorSessionsByKey.keys()) {
    if (key.startsWith(`${clientId}:`)) {
      vectorSessionsByKey.delete(key);
    }
  }

  for (const key of inFlightEmbeddingsByKey.keys()) {
    if (key.startsWith(`${clientId}:`)) {
      inFlightEmbeddingsByKey.delete(key);
    }
  }
}

export function clearAllSemanticIndexes(): void {
  vectorSessionsByKey.clear();
  inFlightEmbeddingsByKey.clear();
  sourceChunkTemplates = new WeakMap();
}

export function getScriptIndexStatus(
  debugId: string,
  index: ScriptSourceIndex,
  settings: SemanticSettings
): { totalChunks: number; embeddedChunks: number; isFullyIndexed: boolean } {
  const script = index.scripts.find((s) => s.debugId === debugId);
  if (!script) return { totalChunks: 0, embeddedChunks: 0, isFullyIndexed: false };

  const templates = chunkTemplatesForSource(script);
  const key = sessionKey(index, settings);
  const session = vectorSessionsByKey.get(key);

  if (!session || templates.length === 0) {
    return { totalChunks: templates.length, embeddedChunks: 0, isFullyIndexed: false };
  }

  let embedded = 0;
  for (const chunk of templates) {
    if (session.vectors.has(chunk.embeddingId)) embedded++;
  }

  return { totalChunks: templates.length, embeddedChunks: embedded, isFullyIndexed: embedded >= templates.length };
}
