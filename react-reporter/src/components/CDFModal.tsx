// CDF modal: shows the full 101-point quantile curve for a histogram.
//
// Triggered by the "CDF" button in any metrics table row. The curve answers
// "is this distribution smooth, or is there a cliff at p90?" — a more
// detailed view than the p50/p95/p99/max columns alone.

import {
  Area,
  AreaChart,
  CartesianGrid,
  ReferenceLine,
  ResponsiveContainer,
  Tooltip as RechartsTooltip,
  XAxis,
  YAxis,
} from "recharts";

import { fmtBytes, fmtN, fmtTsValue, fmtUsShort, fmtVal } from "../format";
import type { CDFInfo } from "../types";

interface CDFModalProps {
  info: CDFInfo | null;
  onClose: () => void;
}

export function CDFModal({ info, onClose }: CDFModalProps) {
  if (!info) return null;
  const { label, hist, unit, key: metricKey } = info;
  if (!hist.cdf) return null;
  const cdf = hist.cdf;
  const data = cdf.map((v, i) => ({ p: i, v }));

  return (
    <div className="Mo" onClick={onClose}>
      <div className="Mb" onClick={(e) => e.stopPropagation()}>
        <div className="Mh">
          <div>
            <div className="Mt">{label} — Distribution</div>
            <div className="Ms">{metricKey}</div>
          </div>
          <button className="Mx" onClick={onClose}>
            ×
          </button>
        </div>

        <div className="Mst">
          {(
            [
              ["Count", fmtN(hist.count)],
              ["Min", fmtVal(hist.min, unit)],
              ["p50", fmtVal(hist.p50, unit)],
              ["p95", fmtVal(hist.p95, unit)],
              ["p99", fmtVal(hist.p99, unit)],
              ["Max", fmtVal(hist.max, unit)],
            ] as const
          ).map(([l, v]) => (
            <div key={l} className="Msi">
              {l}
              <strong>{v}</strong>
            </div>
          ))}
        </div>

        <ResponsiveContainer width="100%" height={300}>
          <AreaChart data={data} margin={{ top: 8, right: 16, bottom: 8, left: 8 }}>
            <CartesianGrid stroke="var(--cg)" strokeDasharray="3 3" vertical={false} />
            <XAxis
              dataKey="p"
              tickFormatter={(v) => `p${v}`}
              ticks={[0, 25, 50, 75, 90, 95, 99, 100]}
              tick={{ fontSize: 11, fill: "var(--cx)" }}
              tickLine={false}
              axisLine={false}
            />
            <YAxis
              tickFormatter={(v) =>
                unit === "bytes" ? fmtBytes(v) : fmtUsShort(v)
              }
              tick={{ fontSize: 11, fill: "var(--cx)" }}
              tickLine={false}
              axisLine={false}
              width={56}
            />
            <RechartsTooltip
              content={({ active, payload }) => {
                if (!active || !payload?.length) return null;
                const pt = payload[0].payload as { p: number; v: number };
                return (
                  <div
                    style={{
                      background: "var(--t1)",
                      color: "#f8fafc",
                      padding: "6px 10px",
                      borderRadius: 6,
                      fontSize: 12,
                      fontFamily: "var(--mono)",
                      boxShadow: "0 4px 12px rgba(0,0,0,.2)",
                    }}
                  >
                    <span style={{ fontWeight: 600 }}>
                      p{pt.p}: {fmtTsValue(pt.v, unit)}
                    </span>
                  </div>
                );
              }}
            />
            <ReferenceLine x={50} stroke="var(--c1)" strokeDasharray="4 3" strokeOpacity={0.4} />
            <ReferenceLine x={95} stroke="var(--c2)" strokeDasharray="4 3" strokeOpacity={0.4} />
            <ReferenceLine x={99} stroke="var(--c3)" strokeDasharray="4 3" strokeOpacity={0.4} />
            <Area
              type="monotone"
              dataKey="v"
              stroke="var(--c1)"
              fill="var(--ca)"
              strokeWidth={2}
              dot={false}
            />
          </AreaChart>
        </ResponsiveContainer>
      </div>
    </div>
  );
}
