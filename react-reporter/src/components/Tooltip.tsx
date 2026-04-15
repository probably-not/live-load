// Custom tooltip used by all chart types in the report.
//
// Pass `unit` to control how values are formatted — this is the fix for
// "WS frame size shown as milliseconds." The unit must match the active
// metric so the tooltip and y-axis agree.

import { fmtTsValue } from "../format";
import type { MetricUnit } from "../types";

interface TTPayload {
  value: number | null;
  name?: string;
  color?: string;
}

interface TTProps {
  active?: boolean;
  payload?: TTPayload[];
  label?: string | number;
  unit: MetricUnit;
}

export function Tooltip({ active, payload, label, unit }: TTProps) {
  if (!active || !payload?.length) return null;
  const valid = payload.filter((p) => p.value != null);
  if (!valid.length) return null;

  return (
    <div
      style={{
        background: "var(--t1)",
        color: "#f8fafc",
        padding: "8px 12px",
        borderRadius: 6,
        fontSize: 12,
        fontFamily: "var(--mono)",
        lineHeight: 1.7,
        boxShadow: "0 4px 12px rgba(0,0,0,.2)",
        maxWidth: 280,
      }}
    >
      <div
        style={{
          fontFamily: "var(--sans)",
          fontWeight: 500,
          opacity: 0.6,
          fontSize: 11,
          marginBottom: 2,
        }}
      >
        {label}
      </div>
      {valid.map((p, i) => (
        <div key={i} style={{ display: "flex", alignItems: "center", gap: 6 }}>
          <span
            style={{
              width: 8,
              height: 3,
              borderRadius: 2,
              background: p.color,
              flexShrink: 0,
            }}
          />
          <span
            style={{
              opacity: 0.7,
              overflow: "hidden",
              textOverflow: "ellipsis",
              whiteSpace: "nowrap",
            }}
          >
            {p.name}:
          </span>
          <span style={{ fontWeight: 600, marginLeft: "auto" }}>
            {fmtTsValue(p.value, unit)}
          </span>
        </div>
      ))}
    </div>
  );
}
