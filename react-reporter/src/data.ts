// Data loading: production reads from window.__LIVELOAD_DATA__ (gzip+base64),
// dev reads from a local JSON file via fetch.
//
// In production, the Elixir reporter replaces the placeholder string in
// index.html with a base64-encoded gzip of the result JSON. In dev mode the
// placeholder remains untouched, and we detect that by checking whether the
// placeholder still has its trademark prefix.
//
// IMPORTANT: The dev-mode comparison must NOT contain the literal injection
// placeholder string, because that would cause the placeholder to appear
// twice in the bundled JS — once in index.html and once inside the loader
// itself. A naive String.replace on the Elixir side would corrupt both
// occurrences. To avoid this we compare against a prefix instead.
//
// Dev mode: drop a JSON file into public/ (e.g. public/dev-data.json) and
// either set VITE_DEV_DATA_PATH or rely on the default "/dev-data.json".

import type { RawData, RawScenarioEntry } from "./types";

// Detect that the placeholder is unreplaced by checking for its prefix.
// This pattern is specific enough to never collide with real base64 data
// (which never contains underscores) but doesn't include the literal
// injection token, so the bundler emits the token only once — inside
// index.html where it belongs.
const DEV_MODE_PREFIX = "__LIVELOAD_DATA_INJECTION";

/** Decompress a base64-encoded gzip blob into the parsed JSON. */
async function decompressData(b64: string): Promise<RawData> {
  // Decode base64 to bytes
  const raw = atob(b64);
  const bytes = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);

  // Feed the bytes through DecompressionStream via Response, which
  // correctly handles backpressure and stream lifecycle for payloads
  // of any size. The manual writer/reader loop we had before worked
  // for small payloads but truncated large ones because writer.write()
  // and writer.close() are async and weren't being awaited.
  const blob = new Blob([bytes]);
  const stream = blob.stream().pipeThrough(new DecompressionStream("gzip"));
  const text = await new Response(stream).text();

  return JSON.parse(text) as RawData;
}

/**
 * Load the report data, normalized to an array of scenario entries.
 *
 * - In production, decompresses window.__LIVELOAD_DATA__.
 * - In dev, fetches a JSON file from public/ (default: /dev-data.json).
 *
 * The runbook's canonical save pattern produces a JSON array. For backward
 * compat we also accept a Record<scenario_name, result> shape.
 */
export async function loadData(): Promise<RawScenarioEntry[]> {
  const placeholder = window.__LIVELOAD_DATA__;
  const isUnreplaced =
    typeof placeholder === "string" && placeholder.startsWith(DEV_MODE_PREFIX);

  let raw: RawData;

  if (isUnreplaced) {
    // Dev mode: fetch JSON from public/
    const path = (import.meta.env.VITE_DEV_DATA_PATH as string | undefined) || "/dev-data.json";
    const response = await fetch(path);
    if (!response.ok) {
      throw new Error(
        `Could not load dev data from ${path}. ` +
          `Drop a JSON file at public/dev-data.json or set VITE_DEV_DATA_PATH.`,
      );
    }
    raw = (await response.json()) as RawData;
  } else {
    // Production mode: decompress the embedded data
    raw = await decompressData(placeholder);
  }

  // Normalize to array form
  if (Array.isArray(raw)) return raw;
  return Object.values(raw);
}
