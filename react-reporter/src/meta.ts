// Display metadata for histograms and counters.
//
// `tsLabel` controls whether a metric appears in the time-series chart selector.
// Histograms whose values represent cumulative durations (like scenario_duration_us)
// don't make sense as a time-series — set tsLabel to null to hide them.
//
// Adding a new metric: add it to HIST_META or COUNTER_META, and to LV_KEYS or
// HTTP_KEYS to control its position in the metrics tables.

import type { HistogramMeta, CounterMeta } from "./types";

export const HIST_META: Record<string, HistogramMeta> = {
  scenario_duration_us: {
    label: "Scenario Duration",
    unit: "us",
    group: "lv",
    tsLabel: null, // cumulative; not meaningful as time-series
  },
  liveview_connection_duration_us: {
    label: "LiveView Connection",
    unit: "us",
    group: "lv",
    tsLabel: "Connection",
  },
  liveview_page_loading_duration_us: {
    label: "Page Loading",
    unit: "us",
    group: "lv",
    tsLabel: "Page Loading",
  },
  liveview_reconnection_duration_us: {
    label: "LiveView Reconnection",
    unit: "us",
    group: "lv",
    tsLabel: "Reconnection",
  },
  liveview_loading_class_duration_us: {
    label: "Loading Class",
    unit: "us",
    group: "lv",
    tsLabel: "Loading Class",
  },
  http_request_duration_us: {
    label: "HTTP Duration",
    unit: "us",
    group: "http",
    tsLabel: "HTTP Total",
  },
  http_request_ttfb_us: {
    label: "HTTP TTFB",
    unit: "us",
    group: "http",
    tsLabel: "TTFB",
  },
  http_request_dns_us: {
    label: "HTTP DNS",
    unit: "us",
    group: "http",
    tsLabel: null,
  },
  http_request_connect_us: {
    label: "HTTP Connect",
    unit: "us",
    group: "http",
    tsLabel: null,
  },
  http_request_tls_us: {
    label: "HTTP TLS",
    unit: "us",
    group: "http",
    tsLabel: null,
  },
  websocket_frame_sent_bytes: {
    label: "WS Frame Sent",
    unit: "bytes",
    group: "http",
    tsLabel: "WS Sent (size)",
  },
  websocket_frame_received_bytes: {
    label: "WS Frame Received",
    unit: "bytes",
    group: "http",
    tsLabel: "WS Received (size)",
  },
};

export const COUNTER_META: Record<string, CounterMeta> = {
  scenario_failures: {
    label: "Scenario Failures",
    tsLabel: "Failures",
  },
  websocket_connections_opened: {
    label: "WS Connections Opened",
    tsLabel: "WS Opened",
  },
  websocket_connections_closed: {
    label: "WS Connections Closed",
    tsLabel: "WS Closed",
  },
  liveview_navigations: {
    label: "LV Navigations",
    tsLabel: "Navigations",
  },
  liveview_disconnections: {
    label: "LV Disconnections",
    tsLabel: "Disconnections",
  },
  liveview_reconnections: {
    label: "LV Reconnections",
    tsLabel: "Reconnections",
  },
  liveview_canceled_loads: {
    label: "LV Canceled Loads",
    tsLabel: "Canceled",
  },
};

/** Order of LiveView metrics in the metrics table. */
export const LV_KEYS = [
  "scenario_duration_us",
  "liveview_connection_duration_us",
  "liveview_page_loading_duration_us",
  "liveview_reconnection_duration_us",
  "liveview_loading_class_duration_us",
];

/** Order of HTTP/WS metrics in the metrics table. */
export const HTTP_KEYS = [
  "http_request_duration_us",
  "http_request_ttfb_us",
  "http_request_dns_us",
  "http_request_connect_us",
  "http_request_tls_us",
  "websocket_frame_sent_bytes",
  "websocket_frame_received_bytes",
];

/** Stable color palette for scenarios in comparison views. */
export const SCENARIO_COLORS = [
  "#6366f1", // indigo
  "#10b981", // emerald
  "#eab308", // yellow
  "#ef4444", // red
  "#8b5cf6", // violet
  "#06b6d4", // cyan
  "#f97316", // orange
  "#ec4899", // pink
];

/** Percentile options for selectors. */
export const PERCENTILE_OPTIONS = [
  { key: "p50", label: "p50" },
  { key: "p95", label: "p95" },
  { key: "p99", label: "p99" },
  { key: "max", label: "max" },
  { key: "mean", label: "mean" },
] as const;

export type PercentileKey = (typeof PERCENTILE_OPTIONS)[number]["key"];
