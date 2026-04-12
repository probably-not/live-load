// Single-scenario report components.
//
// This file contains everything needed to render one ParsedScenario:
// - MetricRow / MetricsTable: histograms with dimensional drill-downs and CDF buttons
// - CounterRow / CountersTable: counters with dimensional drill-downs
// - TimeSeriesCharts: per-scenario time-series with metric selector
// - ScenarioReport: top-level component, orchestrates the above and per-node filtering

import { useMemo, useState } from "react";
import {
  Area,
  AreaChart,
  Bar,
  BarChart,
  CartesianGrid,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip as RechartsTooltip,
  XAxis,
  YAxis,
} from "recharts";

import {
  fmtDur,
  fmtN,
  fmtTime,
  fmtTsValue,
  fmtVal,
  tailClass,
  tailRatio,
} from "../format";
import {
  COUNTER_META,
  HIST_META,
  HTTP_KEYS,
  LV_KEYS,
} from "../meta";
import type {
  CDFInfo,
  ChartSelection,
  MetricUnit,
  ParsedBucket,
  ParsedCounter,
  ParsedDimensionedHistogram,
  ParsedScenario,
} from "../types";
import { CDFModal } from "./CDFModal";
import { Tooltip } from "./Tooltip";

// ─── MetricRow ──────────────────────────────────────────────────────────────────

interface MetricRowProps {
  hKey: string;
  hist: ParsedDimensionedHistogram;
  onCDF: (info: CDFInfo) => void;
}

function MetricRow({ hKey, hist, onCDF }: MetricRowProps) {
  const [open, setOpen] = useState(false);
  const meta = HIST_META[hKey] || { label: hKey, unit: "us" as MetricUnit };
  const a = hist.aggregate;
  const dims = hist.dimensions;
  const dimKeys = Object.keys(dims);
  const hasDims = dimKeys.length > 0;
  const empty = a.empty;
  const u = meta.unit;
  const ratio = empty ? null : tailRatio(a.p99, a.p50);
  const hasCDF = !empty && (a.cdf?.length ?? 0) > 0;

  return (
    <>
      <tr>
        <td>
          <span
            className={`Mn${hasDims ? "" : " ne"}`}
            onClick={hasDims ? () => setOpen(!open) : undefined}
          >
            {hasDims ? (
              <span className={`Ex${open ? " o" : ""}`}>▶</span>
            ) : (
              <span style={{ width: 12, display: "inline-block" }} />
            )}
            {meta.label}
          </span>
        </td>
        <td className={empty ? "z" : ""}>{empty ? "—" : fmtN(a.count)}</td>
        <td className={empty ? "z" : ""}>{empty ? "—" : fmtVal(a.p50, u)}</td>
        <td className={empty ? "z" : ""}>{empty ? "—" : fmtVal(a.p95, u)}</td>
        <td className={empty ? "z" : ""}>{empty ? "—" : fmtVal(a.p99, u)}</td>
        <td className={empty ? "z" : ""}>{empty ? "—" : fmtVal(a.max, u)}</td>
        <td className={empty ? "z" : ""}>{empty ? "—" : fmtVal(a.mean, u)}</td>
        <td>
          {ratio != null ? (
            <span className={`Tb ${tailClass(ratio)}`}>{ratio.toFixed(2)}×</span>
          ) : (
            <span className="z">—</span>
          )}
        </td>
        <td>
          {hasCDF ? (
            <button
              className="Cb"
              onClick={() => onCDF({ key: hKey, label: meta.label, hist: a, unit: u })}
            >
              CDF
            </button>
          ) : null}
        </td>
      </tr>
      {open &&
        dimKeys.map((dk) => {
          const dv = dims[dk];
          const de = dv.empty;
          const dHasCDF = !de && (dv.cdf?.length ?? 0) > 0;
          return (
            <tr key={dk} className="Dr">
              <td>
                <span className="Dl" title={dk}>
                  {dk}
                </span>
              </td>
              <td>{de ? "—" : fmtN(dv.count)}</td>
              <td>{de ? "—" : fmtVal(dv.p50, u)}</td>
              <td>{de ? "—" : fmtVal(dv.p95, u)}</td>
              <td>{de ? "—" : fmtVal(dv.p99, u)}</td>
              <td>{de ? "—" : fmtVal(dv.max, u)}</td>
              <td>{de ? "—" : fmtVal(dv.mean, u)}</td>
              <td></td>
              <td>
                {dHasCDF ? (
                  <button
                    className="Cb"
                    onClick={() =>
                      onCDF({
                        key: hKey,
                        label: `${meta.label} — ${dk}`,
                        hist: dv,
                        unit: u,
                      })
                    }
                  >
                    CDF
                  </button>
                ) : null}
              </td>
            </tr>
          );
        })}
    </>
  );
}

// ─── MetricsTable ───────────────────────────────────────────────────────────────

interface MetricsTableProps {
  title: string;
  badge?: string;
  histograms: Record<string, ParsedDimensionedHistogram>;
  keys: string[];
  onCDF: (info: CDFInfo) => void;
}

function MetricsTable({ title, badge, histograms, keys, onCDF }: MetricsTableProps) {
  return (
    <div className="Se">
      <div className="Sh">
        <span className="Stl">{title}</span>
        {badge && <span className="Sbg">{badge}</span>}
      </div>
      <div className="Tw">
        <table className="T">
          <thead>
            <tr>
              <th>Metric</th>
              <th>Count</th>
              <th>p50</th>
              <th>p95</th>
              <th>p99</th>
              <th>Max</th>
              <th>Mean</th>
              <th
                title={
                  "Tail ratio = p99 ÷ p50. Measures how much worse the slowest requests are vs typical.\nGreen ≤ 2× · Yellow ≤ 4× · Red > 4×"
                }
              >
                Tail ⓘ
              </th>
              <th style={{ width: 44 }}></th>
            </tr>
          </thead>
          <tbody>
            {keys.map((k) =>
              histograms[k] ? (
                <MetricRow key={k} hKey={k} hist={histograms[k]} onCDF={onCDF} />
              ) : null,
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}

// ─── CounterRow / CountersTable ─────────────────────────────────────────────────

interface CounterRowProps {
  cKey: string;
  counter: ParsedCounter;
}

function CounterRow({ cKey, counter }: CounterRowProps) {
  const [open, setOpen] = useState(false);
  const meta = COUNTER_META[cKey] || { label: cKey, tsLabel: null };
  const dims = counter.by;
  const dimKeys = Object.keys(dims).filter((k) => dims[k] > 0);
  const hasDims = dimKeys.length > 0;
  const isZero = counter.aggregate === 0;

  return (
    <>
      <tr>
        <td>
          <span
            className={`Mn${hasDims ? "" : " ne"}`}
            onClick={hasDims ? () => setOpen(!open) : undefined}
          >
            {hasDims ? (
              <span className={`Ex${open ? " o" : ""}`}>▶</span>
            ) : (
              <span style={{ width: 12, display: "inline-block" }} />
            )}
            {meta.label}
          </span>
        </td>
        <td className={isZero ? "z" : ""}>{fmtN(counter.aggregate)}</td>
      </tr>
      {open &&
        dimKeys.map((dk) => (
          <tr key={dk} className="Dr">
            <td>
              <span className="Dl" title={dk}>
                {dk}
              </span>
            </td>
            <td>{fmtN(dims[dk])}</td>
          </tr>
        ))}
    </>
  );
}

interface CountersTableProps {
  counters: Record<string, ParsedCounter>;
}

function CountersTable({ counters }: CountersTableProps) {
  const keys = Object.keys(COUNTER_META).filter((k) => counters[k] != null);
  return (
    <div className="Se">
      <div className="Sh">
        <span className="Stl">Events</span>
      </div>
      <div className="Tw">
        <table className="T" style={{ minWidth: 380 }}>
          <thead>
            <tr>
              <th>Counter</th>
              <th>Total</th>
            </tr>
          </thead>
          <tbody>
            {keys.map((k) => (
              <CounterRow key={k} cKey={k} counter={counters[k]} />
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

// ─── TimeSeriesCharts ───────────────────────────────────────────────────────────

interface TimeSeriesChartsProps {
  ts: ParsedBucket[];
  bucket_width_ms: number;
}

function TimeSeriesCharts({ ts, bucket_width_ms }: TimeSeriesChartsProps) {
  // Histograms with tsLabel that have data in any bucket
  const tsHistograms = useMemo(() => {
    const seen = new Set<string>();
    for (const b of ts) {
      for (const k of Object.keys(b.histograms)) {
        if (HIST_META[k]?.tsLabel) seen.add(k);
      }
    }
    return [...seen].sort();
  }, [ts]);

  // Counters with tsLabel that have data in any bucket
  const tsCounters = useMemo(() => {
    const seen = new Set<string>();
    for (const b of ts) {
      for (const k of Object.keys(b.counters)) {
        if (COUNTER_META[k]?.tsLabel && b.counters[k].aggregate > 0) seen.add(k);
      }
    }
    return [...seen].sort();
  }, [ts]);

  const [selection, setSelection] = useState<ChartSelection>({ kind: "active" });
  const isActive = selection.kind === "active";
  const isHistogram = selection.kind === "histogram";
  const isCounter = selection.kind === "counter";

  // Build data for the active chart. Always covers ALL buckets so empty
  // periods are visible as gaps.
  const chartData = useMemo(() => {
    return ts.map((b) => {
      const label = `${(b.offset_ms / 1000).toFixed(0)}s`;
      if (selection.kind === "active") return { t: label, users: b.active_users };
      if (selection.kind === "histogram") {
        const m = b.histograms[selection.key];
        return {
          t: label,
          p50: m?.p50 ?? null,
          p95: m?.p95 ?? null,
          p99: m?.p99 ?? null,
        };
      }
      if (selection.kind === "counter") {
        const c = b.counters[selection.key];
        return { t: label, count: c?.aggregate ?? null };
      }
      return { t: label };
    });
  }, [ts, selection]);

  const activeLabel = isActive
    ? "Active Users"
    : isHistogram
      ? HIST_META[selection.key]?.label || selection.key
      : COUNTER_META[selection.key]?.label || selection.key;

  // Determine the unit for the active selection so axes and tooltips agree
  const activeUnit: MetricUnit = isActive
    ? "users"
    : isHistogram
      ? HIST_META[selection.key]?.unit || "us"
      : "count";

  return (
    <div className="Se">
      <div className="Sh">
        <span className="Stl">Performance Over Time</span>
        <span className="Sbg">
          {ts.length} buckets × {bucket_width_ms / 1000}s
        </span>
      </div>
      <div className="Cg">
        <div className="Cc">
          <div
            style={{
              display: "flex",
              justifyContent: "space-between",
              alignItems: "center",
              marginBottom: 12,
              flexWrap: "wrap",
              gap: 8,
            }}
          >
            <div className="Ct" style={{ marginBottom: 0 }}>
              {activeLabel}
            </div>
            <div className="Tb2">
              <button
                className={isActive ? "a" : ""}
                onClick={() => setSelection({ kind: "active" })}
              >
                Users
              </button>
              {tsHistograms.map((k) => (
                <button
                  key={k}
                  className={isHistogram && selection.key === k ? "a" : ""}
                  onClick={() => setSelection({ kind: "histogram", key: k })}
                >
                  {HIST_META[k].tsLabel}
                </button>
              ))}
              {tsCounters.map((k) => (
                <button
                  key={k}
                  className={isCounter && selection.key === k ? "a" : ""}
                  onClick={() => setSelection({ kind: "counter", key: k })}
                >
                  {COUNTER_META[k].tsLabel}
                </button>
              ))}
            </div>
          </div>

          {isActive ? (
            <ResponsiveContainer width="100%" height={200}>
              <AreaChart data={chartData} margin={{ top: 4, right: 8, bottom: 4, left: 8 }}>
                <CartesianGrid stroke="var(--cg)" strokeDasharray="3 3" vertical={false} />
                <XAxis
                  dataKey="t"
                  tick={{ fontSize: 11, fill: "var(--cx)" }}
                  tickLine={false}
                  axisLine={false}
                />
                <YAxis
                  tick={{ fontSize: 11, fill: "var(--cx)" }}
                  tickLine={false}
                  axisLine={false}
                  width={32}
                />
                <RechartsTooltip content={<Tooltip unit="users" />} />
                <Area
                  type="stepAfter"
                  dataKey="users"
                  name="Users"
                  stroke="var(--c1)"
                  fill="var(--ca)"
                  strokeWidth={2}
                />
              </AreaChart>
            </ResponsiveContainer>
          ) : isCounter ? (
            <>
              <ResponsiveContainer width="100%" height={240}>
                <BarChart data={chartData} margin={{ top: 4, right: 8, bottom: 4, left: 8 }}>
                  <CartesianGrid stroke="var(--cg)" strokeDasharray="3 3" vertical={false} />
                  <XAxis
                    dataKey="t"
                    tick={{ fontSize: 11, fill: "var(--cx)" }}
                    tickLine={false}
                    axisLine={false}
                  />
                  <YAxis
                    tick={{ fontSize: 11, fill: "var(--cx)" }}
                    tickLine={false}
                    axisLine={false}
                    width={40}
                  />
                  <RechartsTooltip content={<Tooltip unit="count" />} />
                  <Bar
                    dataKey="count"
                    name="Count"
                    fill="var(--c1)"
                    radius={[3, 3, 0, 0]}
                    maxBarSize={32}
                  />
                </BarChart>
              </ResponsiveContainer>
              <div className="Lg">
                <span className="Li">
                  <span className="Ldi" style={{ background: "var(--c1)" }} />
                  events per {bucket_width_ms / 1000}s bucket
                </span>
              </div>
            </>
          ) : (
            <>
              <ResponsiveContainer width="100%" height={240}>
                <LineChart data={chartData} margin={{ top: 4, right: 8, bottom: 4, left: 8 }}>
                  <CartesianGrid stroke="var(--cg)" strokeDasharray="3 3" vertical={false} />
                  <XAxis
                    dataKey="t"
                    tick={{ fontSize: 11, fill: "var(--cx)" }}
                    tickLine={false}
                    axisLine={false}
                  />
                  <YAxis
                    tickFormatter={(v) => fmtTsValue(v, activeUnit)}
                    tick={{ fontSize: 11, fill: "var(--cx)" }}
                    tickLine={false}
                    axisLine={false}
                    width={56}
                  />
                  <RechartsTooltip content={<Tooltip unit={activeUnit} />} />
                  <Line
                    type="monotone"
                    dataKey="p50"
                    name="p50"
                    stroke="var(--c1)"
                    strokeWidth={2}
                    dot={{ r: 3 }}
                    connectNulls={false}
                  />
                  <Line
                    type="monotone"
                    dataKey="p95"
                    name="p95"
                    stroke="var(--c2)"
                    strokeWidth={2}
                    dot={{ r: 3 }}
                    connectNulls={false}
                  />
                  <Line
                    type="monotone"
                    dataKey="p99"
                    name="p99"
                    stroke="var(--c3)"
                    strokeWidth={2}
                    dot={{ r: 3 }}
                    strokeDasharray="4 3"
                    connectNulls={false}
                  />
                </LineChart>
              </ResponsiveContainer>
              <div className="Lg">
                <span className="Li">
                  <span className="Ldi" style={{ background: "var(--c1)" }} /> p50
                </span>
                <span className="Li">
                  <span className="Ldi" style={{ background: "var(--c2)" }} /> p95
                </span>
                <span className="Li">
                  <span className="Ldi" style={{ background: "var(--c3)" }} /> p99
                </span>
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  );
}

// ─── ScenarioReport ─────────────────────────────────────────────────────────────

interface ScenarioReportProps {
  scenario: ParsedScenario;
  activeNode: string | null;
  onSelectNode: (node: string | null) => void;
  onBack: (() => void) | null;
}

export function ScenarioReport({
  scenario,
  activeNode,
  onSelectNode,
  onBack,
}: ScenarioReportProps) {
  const [cdfInfo, setCdfInfo] = useState<CDFInfo | null>(null);
  const s = scenario;

  // Active view: either the global merged result, or one specific node's
  // ScenarioResult. The struct from the Elixir side already provides both;
  // we just pick which one to render against.
  const view = useMemo(() => {
    if (activeNode) {
      const n = s.nodes.find((n) => n.node === activeNode);
      if (n?.result) return n.result;
    }
    return s.global;
  }, [s, activeNode]);

  const pass = view.users.failed === 0;
  const nodeCount = s.nodes.length;
  const multiNode = nodeCount > 1;
  const showingNode = !!activeNode;

  return (
    <>
      {onBack && (
        <button className="Hbk" onClick={onBack}>
          ← Back to comparison
        </button>
      )}
      <div className="Hd">
        <div className="Ht">
          <span className="Hl">LiveLoad</span>
          <span className="Hv">v{s.version}</span>
        </div>
        <div className="Hn">{s.name}</div>
        <div className="Hts">{fmtTime(s.generated_at)}</div>
      </div>

      {showingNode && (
        <div className="Nb">
          <span className="Nb-l">Viewing data from node:</span>
          <span className="Nb-n">{activeNode}</span>
          <button className="Nb-b" onClick={() => onSelectNode(null)}>
            View all nodes
          </button>
        </div>
      )}

      <div className="Cs">
        <div className="C">
          <div className="Cl">Users</div>
          <div className="Cv">{view.users.total}</div>
          <div className="Csb">{view.users.succeeded} succeeded</div>
        </div>
        <div className="C">
          <div className="Cl">Failures</div>
          <div className="Cv" style={{ color: pass ? "var(--ok)" : "var(--er)" }}>
            {view.users.failed}
          </div>
          <div className="Csb">
            {view.users.total > 0
              ? ((view.users.failed / view.users.total) * 100).toFixed(1)
              : "0.0"}
            % rate
          </div>
        </div>
        <div className="C">
          <div className="Cl">Duration</div>
          <div className="Cv">{fmtDur(view.duration_ms)}</div>
          <div className="Csb">{s.bucket_width_ms / 1000}s buckets</div>
        </div>
        <div className="C">
          <div className="Cl">Nodes</div>
          <div className="Cv">{showingNode ? "1" : nodeCount}</div>
          <div className="Csb">
            {showingNode
              ? "(filtered)"
              : pass
                ? "all completed"
                : `${view.users.failed} failed`}
          </div>
        </div>
      </div>

      {multiNode && !showingNode && (
        <div className="Se">
          <div className="Sh">
            <span className="Stl">Cluster Nodes</span>
            <span className="Sbg">click to filter</span>
          </div>
          <div className="Tw">
            <table className="T">
              <thead>
                <tr>
                  <th>Node</th>
                  <th>Status</th>
                  <th>Users</th>
                  <th>Succeeded</th>
                  <th>Failed</th>
                  <th>Duration</th>
                </tr>
              </thead>
              <tbody>
                {s.nodes.map((n) => {
                  const ok = n.status === "ok" && n.result != null;
                  return (
                    <tr key={n.node}>
                      <td>
                        {ok ? (
                          <button className="Nl" onClick={() => onSelectNode(n.node)}>
                            {n.node}
                          </button>
                        ) : (
                          <span
                            style={{
                              fontFamily: "var(--mono)",
                              fontSize: 12,
                              color: "var(--t2)",
                            }}
                          >
                            {n.node}
                          </span>
                        )}
                      </td>
                      <td>
                        <span className={`Tb ${ok ? "Tg" : "Td"}`}>
                          {ok ? "ok" : "error"}
                        </span>
                      </td>
                      <td>{ok ? fmtN(n.result!.users.total) : "—"}</td>
                      <td>{ok ? fmtN(n.result!.users.succeeded) : "—"}</td>
                      <td
                        style={{
                          color:
                            ok && n.result!.users.failed > 0 ? "var(--er)" : undefined,
                        }}
                      >
                        {ok ? fmtN(n.result!.users.failed) : "—"}
                      </td>
                      <td>{ok ? fmtDur(n.result!.duration_ms) : "—"}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      )}

      <MetricsTable
        title="LiveView Performance"
        badge={`${view.users.total} users${
          multiNode && !showingNode ? ` · ${nodeCount} nodes` : ""
        }`}
        histograms={view.histograms}
        keys={LV_KEYS}
        onCDF={setCdfInfo}
      />
      <MetricsTable
        title="HTTP & Network"
        histograms={view.histograms}
        keys={HTTP_KEYS}
        onCDF={setCdfInfo}
      />
      <CountersTable counters={view.counters} />
      {view.time_series.length > 0 && (
        <TimeSeriesCharts ts={view.time_series} bucket_width_ms={s.bucket_width_ms} />
      )}
      {cdfInfo && <CDFModal info={cdfInfo} onClose={() => setCdfInfo(null)} />}
    </>
  );
}
