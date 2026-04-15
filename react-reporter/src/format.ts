// Value formatting helpers used throughout the report.
//
// fmtTsValue is the unified time-series value formatter — it picks the right
// format based on a unit string and is used by both axis labels and tooltips.
// All chart components should call this rather than fmtUs/fmtBytes directly.

import type { MetricUnit } from "./types";

/** Format a microsecond value as a human-readable duration. */
export function fmtUs(us: number | null | undefined): string {
  if (us == null || us === 0) return "0";
  const a = Math.abs(us);
  if (a < 1000) return `${Math.round(us)}µs`;
  if (a < 1_000_000) return `${(us / 1000).toFixed(a < 100_000 ? 1 : 0)}ms`;
  return `${(us / 1_000_000).toFixed(2)}s`;
}

/** Format a byte count as B / KB / MB. */
export function fmtBytes(b: number | null | undefined): string {
  if (b == null) return "—";
  if (b < 1024) return `${Math.round(b)} B`;
  if (b < 1_048_576) return `${(b / 1024).toFixed(1)} KB`;
  return `${(b / 1_048_576).toFixed(2)} MB`;
}

/** Format a value based on its unit. Used in tables. */
export function fmtVal(v: number | null | undefined, unit: MetricUnit): string {
  if (v == null) return "—";
  if (unit === "bytes") return fmtBytes(v);
  if (unit === "users" || unit === "count") return fmtN(v);
  return fmtUs(v);
}

/**
 * Compact duration formatter for chart axis labels.
 * Single-line, integer-rounded so labels stay short.
 */
export function fmtUsShort(us: number | null | undefined): string {
  if (!us) return "0";
  const a = Math.abs(us);
  if (a < 1000) return `${Math.round(us)}µs`;
  if (a < 1_000_000) return `${Math.round(us / 1000)}ms`;
  return `${(us / 1_000_000).toFixed(1)}s`;
}

/**
 * Unified time-series value formatter — used by both axis labels and tooltips.
 * Pass the unit of the active metric so it picks the right format. This is the
 * fix for the "WS frame size shown as milliseconds" bug — every chart that
 * formats a y-value should go through here, not fmtUsShort directly.
 */
export function fmtTsValue(v: number | null | undefined, unit: MetricUnit): string {
  if (v == null) return "—";
  if (unit === "users" || unit === "count") return v.toLocaleString();
  if (unit === "bytes") return fmtBytes(v);
  return fmtUsShort(v); // default: microseconds
}

/** Format an integer count with thousands separators. */
export function fmtN(n: number | null | undefined): string {
  return n?.toLocaleString() ?? "—";
}

/** Format an ISO timestamp as a readable local date/time. */
export function fmtTime(iso: string | null | undefined): string {
  if (!iso) return "";
  try {
    return new Date(iso).toLocaleString(undefined, {
      year: "numeric",
      month: "short",
      day: "numeric",
      hour: "2-digit",
      minute: "2-digit",
    });
  } catch {
    return iso;
  }
}

/** Format a millisecond duration as a short human string. */
export function fmtDur(ms: number): string {
  const s = ms / 1000;
  if (s < 60) return `${s.toFixed(1)}s`;
  return `${Math.floor(s / 60)}m ${Math.round(s % 60)}s`;
}

/**
 * Strip the "Elixir." prefix and pick the last two segments of a module name.
 * "Elixir.LiveLoadBench.Scenarios.Mount.Sync" → "Mount.Sync"
 */
export function shortName(name: string | null | undefined): string {
  if (!name) return "";
  const s = name.replace(/^Elixir\./, "");
  const parts = s.split(".");
  if (parts.length >= 3) return parts.slice(-2).join(".");
  return s;
}

/**
 * Compute the tail ratio (p99 / p50). Returns null when p50 is zero or missing.
 * Used to flag metrics with bad tail latency.
 */
export function tailRatio(p99: number | undefined, p50: number | undefined): number | null {
  if (!p50 || !p99) return null;
  return p99 / p50;
}

/** Map a tail ratio to a CSS class for color coding. */
export function tailClass(ratio: number | null): string {
  if (ratio == null) return "";
  if (ratio <= 2) return "Tg";
  if (ratio <= 4) return "Twn";
  return "Td";
}
