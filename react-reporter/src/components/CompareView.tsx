// Multi-scenario comparison view.
//
// This is the default landing view when there are 2+ scenarios. The filter
// chips at the top let you toggle scenarios in and out, and every table
// and chart re-computes from the selected subset.
//
// Components:
// - ScenarioFilter: chip selector for active scenarios
// - CompareMetricsTable: rows = metrics, columns = scenarios; lowest cell highlighted
// - CompareCountersTable: same shape but for counters (no "best" highlighting)
// - CompareTimeSeries: one line per scenario for a chosen metric & percentile
// - ComparisonView: orchestrates everything above

import { useEffect, useMemo, useState } from "react";
import {
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

import { fmtDur, fmtN, fmtTime, fmtTsValue, fmtVal, shortName } from "../format";
import {
  COUNTER_META,
  HIST_META,
  HTTP_KEYS,
  LV_KEYS,
  PERCENTILE_OPTIONS,
  type PercentileKey,
} from "../meta";
import type {
  ChartSelection,
  MetricUnit,
  ParsedBucket,
  ParsedScenarioEntry,
} from "../types";
import { Tooltip } from "./Tooltip";

// ─── ScenarioFilter ─────────────────────────────────────────────────────────────

interface ScenarioFilterProps {
  scenarios: ParsedScenarioEntry[];
  selected: number[];
  onChange: (selected: number[]) => void;
  colors: string[];
}

export function ScenarioFilter({
  scenarios,
  selected,
  onChange,
  colors,
}: ScenarioFilterProps) {
  const all = scenarios.map((_, i) => i);
  return (
    <div className="Fl">
      <span className="Flh">Scenarios</span>
      {scenarios.map((s, i) => {
        const on = selected.includes(i);
        return (
          <button
            key={i}
            className={`Fc${on ? " on" : ""}`}
            onClick={() => {
              if (on && selected.length === 1) return; // never deselect last
              onChange(
                on
                  ? selected.filter((x) => x !== i)
                  : [...selected, i].sort((a, b) => a - b),
              );
            }}
          >
            <span
              className="dt"
              style={{ background: on ? colors[i] : "var(--b1)" }}
            />
            {shortName(s.name)}
            {s.error && " ⚠"}
          </button>
        );
      })}
      <div className="Fla">
        <button onClick={() => onChange(all)}>All</button>
      </div>
    </div>
  );
}

// ─── CompareMetricsTable ────────────────────────────────────────────────────────

interface CompareMetricsTableProps {
  title: string;
  scenarios: ParsedScenarioEntry[];
  indices: number[];
  colors: string[];
  keys: string[];
  onDrillIn: (idx: number) => void;
}

function CompareMetricsTable({
  title,
  scenarios,
  indices,
  colors,
  keys,
  onDrillIn,
}: CompareMetricsTableProps) {
  const [pct, setPct] = useState<PercentileKey>("p95");

  // Only show metrics that have data in at least one selected scenario
  const activeKeys = keys.filter((k) =>
    indices.some((i) => {
      const s = scenarios[i];
      if (s.error) return false;
      const h = s.global.histograms[k];
      return h && !h.aggregate.empty;
    }),
  );

  if (activeKeys.length === 0) return null;

  return (
    <div className="Se">
      <div className="Sh">
        <span className="Stl">{title}</span>
        <span className="Sbg">{indices.length} scenarios</span>
        <div className="Sht">
          <span
            style={{
              fontSize: 11,
              color: "var(--t3)",
              textTransform: "uppercase",
              letterSpacing: ".05em",
              fontWeight: 600,
            }}
          >
            Compare by
          </span>
          <div className="Tb2">
            {PERCENTILE_OPTIONS.map((o) => (
              <button
                key={o.key}
                className={pct === o.key ? "a" : ""}
                onClick={() => setPct(o.key)}
              >
                {o.label}
              </button>
            ))}
          </div>
        </div>
      </div>
      <div className="Tw">
        <table className="T">
          <thead>
            <tr>
              <th>Metric</th>
              {indices.map((i) => (
                <th
                  key={i}
                  style={{
                    color: colors[i],
                    fontWeight: 600,
                    cursor: "pointer",
                  }}
                  onClick={() => onDrillIn(i)}
                  title="Click to drill into this scenario"
                >
                  {shortName(scenarios[i].name)}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {activeKeys.map((k) => {
              const meta = HIST_META[k];
              const u = meta.unit;
              const cells = indices.map((i) => {
                const s = scenarios[i];
                if (s.error) return { value: null as number | null };
                const h = s.global.histograms[k];
                if (!h || h.aggregate.empty) return { value: null };
                return { value: h.aggregate[pct] ?? null };
              });
              const valid = cells.filter(
                (c): c is { value: number } => c.value != null,
              );
              const minVal =
                valid.length >= 2 ? Math.min(...valid.map((c) => c.value)) : null;
              return (
                <tr key={k}>
                  <td>{meta.label}</td>
                  {cells.map((c, ci) => (
                    <td
                      key={ci}
                      className={
                        c.value != null && c.value === minVal
                          ? "best"
                          : c.value == null
                            ? "z"
                            : ""
                      }
                    >
                      {c.value == null ? "—" : fmtVal(c.value, u)}
                    </td>
                  ))}
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
      <div style={{ fontSize: 11, color: "var(--t3)", marginTop: 6, padding: "0 4px" }}>
        Lowest value per row highlighted in green. Click a scenario header to drill in.
      </div>
    </div>
  );
}

// ─── CompareCountersTable ───────────────────────────────────────────────────────

interface CompareCountersTableProps {
  scenarios: ParsedScenarioEntry[];
  indices: number[];
  colors: string[];
  onDrillIn: (idx: number) => void;
}

function CompareCountersTable({
  scenarios,
  indices,
  colors,
  onDrillIn,
}: CompareCountersTableProps) {
  // Collect all counter keys that have non-zero values across selected scenarios
  const allKeys = new Set<string>();
  for (const i of indices) {
    const s = scenarios[i];
    if (s.error) continue;
    for (const [k, c] of Object.entries(s.global.counters)) {
      if (c.aggregate > 0) allKeys.add(k);
    }
  }
  const keys = [...allKeys].sort();
  if (keys.length === 0) return null;

  return (
    <div className="Se">
      <div className="Sh">
        <span className="Stl">Events</span>
      </div>
      <div className="Tw">
        <table className="T">
          <thead>
            <tr>
              <th>Counter</th>
              {indices.map((i) => (
                <th
                  key={i}
                  style={{ color: colors[i], fontWeight: 600, cursor: "pointer" }}
                  onClick={() => onDrillIn(i)}
                  title="Click to drill into this scenario"
                >
                  {shortName(scenarios[i].name)}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {keys.map((k) => {
              const meta = COUNTER_META[k] || { label: k };
              return (
                <tr key={k}>
                  <td>{meta.label}</td>
                  {indices.map((i) => {
                    const s = scenarios[i];
                    if (s.error)
                      return (
                        <td key={i} className="z">
                          —
                        </td>
                      );
                    const c = s.global.counters[k];
                    const v = c?.aggregate ?? 0;
                    return (
                      <td key={i} className={v === 0 ? "z" : ""}>
                        {fmtN(v)}
                      </td>
                    );
                  })}
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}

// ─── CompareTimeSeries ──────────────────────────────────────────────────────────

interface CompareTimeSeriesProps {
  scenarios: ParsedScenarioEntry[];
  indices: number[];
  colors: string[];
}

function CompareTimeSeries({ scenarios, indices, colors }: CompareTimeSeriesProps) {
  const tsHistograms = useMemo(() => {
    const seen = new Set<string>();
    for (const i of indices) {
      const s = scenarios[i];
      if (s.error) continue;
      for (const b of s.global.time_series) {
        for (const k of Object.keys(b.histograms)) {
          if (HIST_META[k]?.tsLabel) seen.add(k);
        }
      }
    }
    return [...seen].sort();
  }, [scenarios, indices]);

  const tsCounters = useMemo(() => {
    const seen = new Set<string>();
    for (const i of indices) {
      const s = scenarios[i];
      if (s.error) continue;
      for (const b of s.global.time_series) {
        for (const k of Object.keys(b.counters)) {
          if (COUNTER_META[k]?.tsLabel && b.counters[k].aggregate > 0) seen.add(k);
        }
      }
    }
    return [...seen].sort();
  }, [scenarios, indices]);

  const [selection, setSelection] = useState<ChartSelection | null>(null);
  const [pct, setPct] = useState<PercentileKey>("p95");

  // Initialize the selection once we know which metrics are available
  useEffect(() => {
    if (selection != null) return;
    if (tsHistograms.length > 0) {
      setSelection({ kind: "histogram", key: tsHistograms[0] });
    } else if (tsCounters.length > 0) {
      setSelection({ kind: "counter", key: tsCounters[0] });
    }
  }, [tsHistograms, tsCounters, selection]);

  // Build chart data from the union of all bucket offsets across selected scenarios
  const chartData = useMemo(() => {
    if (!selection || selection.kind === "active") return [];
    const offsets = new Set<number>();
    for (const i of indices) {
      const s = scenarios[i];
      if (s.error) continue;
      for (const b of s.global.time_series) offsets.add(b.offset_ms);
    }
    const sortedOffsets = [...offsets].sort((a, b) => a - b);

    // Pre-build offset → bucket maps so lookup is O(1) instead of O(n)
    const bucketMaps = new Map<number, Map<number, ParsedBucket>>();
    for (const i of indices) {
      const s = scenarios[i];
      if (s.error) continue;
      const m = new Map<number, ParsedBucket>();
      for (const b of s.global.time_series) m.set(b.offset_ms, b);
      bucketMaps.set(i, m);
    }

    return sortedOffsets.map((offset_ms) => {
      const row: Record<string, string | number | null> = {
        t: `${(offset_ms / 1000).toFixed(0)}s`,
      };
      for (const i of indices) {
        const s = scenarios[i];
        if (s.error) {
          row[`s${i}`] = null;
          continue;
        }
        const b = bucketMaps.get(i)?.get(offset_ms);
        if (!b) {
          row[`s${i}`] = null;
          continue;
        }
        if (selection.kind === "histogram") {
          const m = b.histograms[selection.key];
          row[`s${i}`] = m ? (m[pct] ?? null) : null;
        } else if (selection.kind === "counter") {
          const c = b.counters[selection.key];
          row[`s${i}`] = c ? c.aggregate : null;
        }
      }
      return row;
    });
  }, [scenarios, indices, selection, pct]);

  if (!selection) return null;
  const isHistogram = selection.kind === "histogram";
  const isCounter = selection.kind === "counter";

  const activeLabel = isHistogram
    ? HIST_META[selection.key]?.label || selection.key
    : isCounter
      ? COUNTER_META[selection.key]?.label || selection.key
      : "";

  const chartUnit: MetricUnit = isHistogram
    ? HIST_META[selection.key]?.unit || "us"
    : "count";

  return (
    <div className="Se">
      <div className="Sh">
        <span className="Stl">Compare Over Time</span>
        <div className="Sht">
          {isHistogram && (
            <>
              <span
                style={{
                  fontSize: 11,
                  color: "var(--t3)",
                  textTransform: "uppercase",
                  letterSpacing: ".05em",
                  fontWeight: 600,
                }}
              >
                Percentile
              </span>
              <div className="Tb2">
                {PERCENTILE_OPTIONS.slice(0, 4).map((o) => (
                  <button
                    key={o.key}
                    className={pct === o.key ? "a" : ""}
                    onClick={() => setPct(o.key)}
                  >
                    {o.label}
                  </button>
                ))}
              </div>
            </>
          )}
        </div>
      </div>
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
            {isHistogram ? ` — ${pct}` : ""}
          </div>
          <div className="Tb2">
            {tsHistograms.map((k) => (
              <button
                key={`h${k}`}
                className={isHistogram && selection.key === k ? "a" : ""}
                onClick={() => setSelection({ kind: "histogram", key: k })}
              >
                {HIST_META[k].tsLabel}
              </button>
            ))}
            {tsCounters.map((k) => (
              <button
                key={`c${k}`}
                className={isCounter && selection.key === k ? "a" : ""}
                onClick={() => setSelection({ kind: "counter", key: k })}
              >
                {COUNTER_META[k].tsLabel}
              </button>
            ))}
          </div>
        </div>
        {isCounter ? (
          <ResponsiveContainer width="100%" height={280}>
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
              <RechartsTooltip
                content={(props) => <Tooltip {...(props as any)} unit="count" />}
              />
              {indices.map((i) => (
                <Bar
                  key={i}
                  dataKey={`s${i}`}
                  name={shortName(scenarios[i].name)}
                  fill={colors[i]}
                  radius={[2, 2, 0, 0]}
                  maxBarSize={20}
                />
              ))}
            </BarChart>
          </ResponsiveContainer>
        ) : (
          <ResponsiveContainer width="100%" height={280}>
            <LineChart data={chartData} margin={{ top: 4, right: 8, bottom: 4, left: 8 }}>
              <CartesianGrid stroke="var(--cg)" strokeDasharray="3 3" vertical={false} />
              <XAxis
                dataKey="t"
                tick={{ fontSize: 11, fill: "var(--cx)" }}
                tickLine={false}
                axisLine={false}
              />
              <YAxis
                tickFormatter={(v) => fmtTsValue(v, chartUnit)}
                tick={{ fontSize: 11, fill: "var(--cx)" }}
                tickLine={false}
                axisLine={false}
                width={56}
              />
              <RechartsTooltip
                content={(props) => <Tooltip {...(props as any)} unit={chartUnit} />}
              />
              {indices.map((i) => (
                <Line
                  key={i}
                  type="monotone"
                  dataKey={`s${i}`}
                  name={shortName(scenarios[i].name)}
                  stroke={colors[i]}
                  strokeWidth={2}
                  dot={{ r: 3 }}
                  connectNulls={false}
                />
              ))}
            </LineChart>
          </ResponsiveContainer>
        )}
        <div className="Lg">
          {indices.map((i) => (
            <span key={i} className="Li">
              <span className="Ldi" style={{ background: colors[i] }} />
              {shortName(scenarios[i].name)}
            </span>
          ))}
        </div>
      </div>
    </div>
  );
}

// ─── ComparisonView ─────────────────────────────────────────────────────────────

interface ComparisonViewProps {
  scenarios: ParsedScenarioEntry[];
  indices: number[];
  colors: string[];
  onDrillIn: (idx: number) => void;
  onChangeSelection: (selected: number[]) => void;
}

export function ComparisonView({
  scenarios,
  indices,
  colors,
  onDrillIn,
  onChangeSelection,
}: ComparisonViewProps) {
  const totals = useMemo(() => {
    let users = 0;
    let succeeded = 0;
    let failed = 0;
    let maxDuration = 0;
    let nodes = 0;
    let scenariosOk = 0;
    let scenariosErr = 0;
    for (const i of indices) {
      const s = scenarios[i];
      if (s.error) {
        scenariosErr++;
        continue;
      }
      scenariosOk++;
      users += s.global.users.total;
      succeeded += s.global.users.succeeded;
      failed += s.global.users.failed;
      if (s.global.duration_ms > maxDuration) maxDuration = s.global.duration_ms;
      nodes += s.nodes.length;
    }
    return { users, succeeded, failed, maxDuration, nodes, scenariosOk, scenariosErr };
  }, [scenarios, indices]);

  const firstOk = scenarios.find((s) => !s.error);
  const generated = firstOk && !firstOk.error ? firstOk.generated_at : null;
  const version = firstOk && !firstOk.error ? firstOk.version : null;

  return (
    <>
      <div className="Hd">
        <div className="Ht">
          <span className="Hl">LiveLoad</span>
          {version && <span className="Hv">v{version}</span>}
        </div>
        <div className="Hn">
          {scenarios.length === 1
            ? scenarios[0].name
            : `Comparing ${indices.length} of ${scenarios.length} scenarios`}
        </div>
        {generated && <div className="Hts">{fmtTime(generated)}</div>}
      </div>

      <ScenarioFilter
        scenarios={scenarios}
        selected={indices}
        onChange={onChangeSelection}
        colors={colors}
      />

      <div className="Cs">
        <div className="C">
          <div className="Cl">Total Users</div>
          <div className="Cv">{fmtN(totals.users)}</div>
          <div className="Csb">{fmtN(totals.succeeded)} succeeded</div>
        </div>
        <div className="C">
          <div className="Cl">Failures</div>
          <div
            className="Cv"
            style={{ color: totals.failed === 0 ? "var(--ok)" : "var(--er)" }}
          >
            {fmtN(totals.failed)}
          </div>
          <div className="Csb">
            {totals.users > 0 ? ((totals.failed / totals.users) * 100).toFixed(1) : "0.0"}
            % rate
          </div>
        </div>
        <div className="C">
          <div className="Cl">Longest Duration</div>
          <div className="Cv">{fmtDur(totals.maxDuration)}</div>
          <div className="Csb">across {indices.length} scenarios</div>
        </div>
        <div className="C">
          <div className="Cl">Scenarios</div>
          <div className="Cv">
            {totals.scenariosOk}
            {totals.scenariosErr > 0 && (
              <span style={{ color: "var(--er)", fontSize: 14 }}>
                {" "}
                +{totals.scenariosErr} ⚠
              </span>
            )}
          </div>
          <div className="Csb">{fmtN(totals.nodes)} nodes total</div>
        </div>
      </div>

      {indices.length >= 2 ? (
        <>
          <CompareMetricsTable
            title="LiveView Performance"
            scenarios={scenarios}
            indices={indices}
            colors={colors}
            keys={LV_KEYS}
            onDrillIn={onDrillIn}
          />
          <CompareMetricsTable
            title="HTTP & Network"
            scenarios={scenarios}
            indices={indices}
            colors={colors}
            keys={HTTP_KEYS}
            onDrillIn={onDrillIn}
          />
          <CompareCountersTable
            scenarios={scenarios}
            indices={indices}
            colors={colors}
            onDrillIn={onDrillIn}
          />
          <CompareTimeSeries scenarios={scenarios} indices={indices} colors={colors} />
          <div className="Se">
            <div className="Sh">
              <span className="Stl">Drill into a scenario</span>
            </div>
            <div style={{ display: "flex", flexWrap: "wrap", gap: 8 }}>
              {indices.map((i) => (
                <button
                  key={i}
                  className="Dc"
                  onClick={() => onDrillIn(i)}
                  style={{
                    border: `1px solid ${colors[i]}`,
                    color: colors[i],
                  }}
                >
                  {shortName(scenarios[i].name)} →
                </button>
              ))}
            </div>
          </div>
        </>
      ) : indices.length === 1 ? (
        <div
          style={{
            textAlign: "center",
            padding: "32px 20px",
            background: "var(--s1)",
            border: "1px solid var(--b1)",
            borderRadius: 8,
            color: "var(--t2)",
            fontSize: 13,
          }}
        >
          Only 1 scenario selected.{" "}
          <button
            onClick={() => onDrillIn(indices[0])}
            style={{
              background: "none",
              border: "none",
              color: "var(--a1)",
              cursor: "pointer",
              font: "inherit",
              textDecoration: "underline",
            }}
          >
            Drill into {shortName(scenarios[indices[0]].name)}
          </button>{" "}
          for the full report.
        </div>
      ) : null}
    </>
  );
}
