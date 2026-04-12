// Parser: raw LiveLoad.Result JSON → display-ready ParsedScenario.
//
// The parser is responsible for:
// 1. Extracting display stats (p50/p95/p99/etc) from PrecomputedQuantiles arrays
// 2. Skipping empty histograms gracefully
// 3. Detecting error scenarios from the wrapped {name, error} shape
// 4. Producing a single ParsedScenarioEntry per input scenario

import type {
  RawScenarioEntry,
  RawLiveLoadResult,
  RawErrorScenario,
  RawScenarioResult,
  RawPrecomputedQuantiles,
  RawDimensionedCounter,
  ParsedScenario,
  ParsedErrorScenario,
  ParsedScenarioEntry,
  ParsedScenarioResult,
  ParsedHistogramStats,
  ParsedDimensionedHistogram,
  ParsedCounter,
  ParsedBucket,
  ParsedNode,
} from "./types";

/** Parse a PrecomputedQuantiles entry into display stats. */
export function parseHist(
  h: RawPrecomputedQuantiles | null | undefined,
): ParsedHistogramStats {
  if (!h || h.count === 0) return { count: 0, empty: true };
  const v = h.values;
  return {
    count: h.count,
    sum: h.sum,
    min: v[0],
    p50: v[50],
    p75: v[75],
    p90: v[90],
    p95: v[95],
    p99: v[99],
    max: v[100],
    mean: h.sum / h.count,
    cdf: v,
    empty: false,
  };
}

/** Parse a DimensionedCounter — already nearly the right shape, just normalize defaults. */
export function parseCounter(
  c: RawDimensionedCounter | null | undefined,
): ParsedCounter {
  if (c == null) return { aggregate: 0, by: {} };
  return { aggregate: c.aggregate || 0, by: c.by || {} };
}

/** Parse a ScenarioResult (either global or per-node). */
export function parseScenarioResult(
  sr: RawScenarioResult,
): ParsedScenarioResult {
  const histograms: Record<string, ParsedDimensionedHistogram> = {};
  for (const [k, h] of Object.entries(sr.histograms || {})) {
    const aggregate = parseHist(h.aggregate);
    const dimensions: Record<string, ParsedHistogramStats> = {};
    for (const [dk, dv] of Object.entries(h.by || {})) {
      dimensions[dk] = parseHist(dv);
    }
    histograms[k] = { aggregate, dimensions };
  }

  const counters: Record<string, ParsedCounter> = {};
  for (const [k, c] of Object.entries(sr.counters || {})) {
    counters[k] = parseCounter(c);
  }

  const time_series: ParsedBucket[] = (sr.time_series || []).map((b) => {
    const bHistograms: Record<string, ParsedHistogramStats> = {};
    for (const [mk, mh] of Object.entries(b.histograms || {})) {
      const parsed = parseHist(mh.aggregate);
      // Per-bucket histograms are dropped if empty — saves chart loop work
      if (!parsed.empty) bHistograms[mk] = parsed;
    }
    const bCounters: Record<string, ParsedCounter> = {};
    for (const [ck, cc] of Object.entries(b.counters || {})) {
      bCounters[ck] = parseCounter(cc);
    }
    return {
      offset_ms: b.offset_ms,
      active_users: b.active_users,
      node_count: b.node_count,
      histograms: bHistograms,
      counters: bCounters,
    };
  });

  return {
    users: sr.users,
    duration_ms: sr.duration_ms,
    histograms,
    counters,
    time_series,
    failure_samples: sr.failure_samples ?? {},
  };
}

/** Type guard: is this a successful LiveLoad.Result or an error wrapper? */
function isErrorScenario(raw: RawScenarioEntry): raw is RawErrorScenario {
  return "error" in raw && raw.error != null && !("global" in raw);
}

/** Parse a single scenario entry, handling both success and error shapes. */
export function parseScenario(raw: RawScenarioEntry): ParsedScenarioEntry {
  if (isErrorScenario(raw)) {
    const err: ParsedErrorScenario = {
      error: true,
      name: raw.name || raw.scenario || "Unknown",
      reason: raw.error,
    };
    return err;
  }

  const r = raw as RawLiveLoadResult;
  const global = parseScenarioResult(r.global);

  const nodes: ParsedNode[] = (r.nodes || []).map((n) => {
    if (n.status === "error" || !n.result) {
      return { node: n.node, status: "error" as const, result: null };
    }
    return {
      node: n.node,
      status: "ok" as const,
      result: parseScenarioResult(n.result),
    };
  });

  const scenario: ParsedScenario = {
    error: false,
    name: r.name,
    generated_at: r.generated_at,
    version: r.liveload_version,
    bucket_width_ms: r.bucket_width_ms,
    global,
    nodes,
  };
  return scenario;
}
