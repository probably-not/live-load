// TypeScript types for the LiveLoad HTML reporter.
//
// The "Raw" types mirror the JSON shape produced by LiveLoad.Result.encode/1.
// They should match the Elixir struct definitions in lib/live_load/result.ex
// exactly. If the struct evolves, update both sides together.
//
// The "Parsed" types are the in-memory shapes the React components consume.
// The parser in src/parse.ts converts raw → parsed.

// ─── Raw JSON shapes ────────────────────────────────────────────────────────────

/** PrecomputedQuantiles: 101-point quantile curve at 0%, 1%, ... 100%. */
export interface RawPrecomputedQuantiles {
  count: number;
  sum: number;
  values: number[]; // length 101
}

/** A histogram with both an aggregate curve and a per-dimension breakdown. */
export interface RawDimensionedHistogram {
  aggregate: RawPrecomputedQuantiles;
  by: Record<string, RawPrecomputedQuantiles>;
}

/** A counter with both an aggregate count and a per-dimension breakdown. */
export interface RawDimensionedCounter {
  aggregate: number;
  by: Record<string, number>;
}

/** One time-series bucket within a scenario run. */
export interface RawBucket {
  offset_ms: number;
  active_users: number;
  /** How many nodes contributed to this bucket. `null` for per-node breakdowns. */
  node_count: number | null;
  histograms: Record<string, RawDimensionedHistogram>;
  counters: Record<string, RawDimensionedCounter>;
}

export interface RawUsers {
  total: number;
  succeeded: number;
  failed: number;
}

/**
 * A sample of a failed scenario user, captured for debugging.
 * The category key (in failure_samples) is the failure classification.
 */
export interface RawFailureSample {
  kind: "throw" | "error" | "exit";
  reason_inspect: string;
  stacktrace: string[];
  monotonic_time: number;
  user_id: unknown;
}

/** A successful scenario result, either global (cluster-wide) or per-node. */
export interface RawScenarioResult {
  users: RawUsers;
  duration_ms: number;
  histograms: Record<string, RawDimensionedHistogram>;
  counters: Record<string, RawDimensionedCounter>;
  time_series: RawBucket[];
  /** Optional: older reports from before failure samples landed won't have this field. */
  failure_samples?: Record<string, RawFailureSample[]>;
}

export interface RawNodeResult {
  node: string;
  status: "ok" | "error";
  result: RawScenarioResult | null;
}

/** The full LiveLoad.Result struct as serialized to JSON. */
export interface RawLiveLoadResult {
  name: string;
  generated_at: string; // ISO 8601
  liveload_version: string;
  bucket_width_ms: number;
  global: RawScenarioResult;
  nodes: RawNodeResult[];
  quantile_points: number[];
}

/**
 * A failed scenario as wrapped by the runbook's save pattern:
 * `{scenario, {:error, reason}} -> %{name: ..., error: ...}`.
 * This is what appears in the array when a scenario errored out entirely.
 */
export interface RawErrorScenario {
  name?: string;
  scenario?: string;
  error: string;
}

export type RawScenarioEntry = RawLiveLoadResult | RawErrorScenario;

/**
 * Top-level: an array of scenarios per the runbook canonical save pattern.
 * For backward compatibility we also accept a Record<scenario, result>.
 */
export type RawData = RawScenarioEntry[] | Record<string, RawScenarioEntry>;

// ─── Parsed display shapes ──────────────────────────────────────────────────────

/** Display-ready stats extracted from a PrecomputedQuantiles entry. */
export interface ParsedHistogramStats {
  count: number;
  sum?: number;
  min?: number;
  p50?: number;
  p75?: number;
  p90?: number;
  p95?: number;
  p99?: number;
  max?: number;
  mean?: number;
  /** All 101 quantile values, only present on aggregate (not per-bucket). */
  cdf?: number[];
  /** True when count === 0; signals "no data, render as —". */
  empty: boolean;
}

export interface ParsedDimensionedHistogram {
  aggregate: ParsedHistogramStats;
  dimensions: Record<string, ParsedHistogramStats>;
}

export interface ParsedCounter {
  aggregate: number;
  by: Record<string, number>;
}

export interface ParsedBucket {
  offset_ms: number;
  active_users: number;
  node_count: number | null;
  /** Bucket histograms only carry aggregate stats, no per-dimension. */
  histograms: Record<string, ParsedHistogramStats>;
  counters: Record<string, ParsedCounter>;
}

export type ParsedFailureSample = RawFailureSample;

export interface ParsedScenarioResult {
  users: RawUsers;
  duration_ms: number;
  histograms: Record<string, ParsedDimensionedHistogram>;
  counters: Record<string, ParsedCounter>;
  time_series: ParsedBucket[];
  failure_samples: Record<string, ParsedFailureSample[]>;
}

export interface ParsedNode {
  node: string;
  status: "ok" | "error";
  result: ParsedScenarioResult | null;
}

export interface ParsedScenario {
  error: false;
  name: string;
  generated_at: string;
  version: string;
  bucket_width_ms: number;
  global: ParsedScenarioResult;
  nodes: ParsedNode[];
}

export interface ParsedErrorScenario {
  error: true;
  name: string;
  reason: string;
}

export type ParsedScenarioEntry = ParsedScenario | ParsedErrorScenario;

// ─── Display metadata ───────────────────────────────────────────────────────────

/** Unit a metric value carries — drives both formatting and chart axis labels. */
export type MetricUnit = "us" | "bytes" | "users" | "count";

export interface HistogramMeta {
  label: string;
  unit: MetricUnit;
  group: "lv" | "http";
  /** Display label in time-series chart selector; null = not chartable. */
  tsLabel: string | null;
}

export interface CounterMeta {
  label: string;
  /** Display label in time-series chart selector; null = not chartable. */
  tsLabel: string | null;
}

// ─── Component state types ──────────────────────────────────────────────────────

/** Info passed to the CDF modal when a CDF button is clicked. */
export interface CDFInfo {
  key: string;
  label: string;
  hist: ParsedHistogramStats;
  unit: MetricUnit;
}

/** What's currently selected in a time-series chart selector. */
export type ChartSelection =
  | { kind: "active" }
  | { kind: "histogram"; key: string }
  | { kind: "counter"; key: string };

/** Augment the global Window type with the data placeholder. */
declare global {
  interface Window {
    __LIVELOAD_DATA__: string;
  }
}
