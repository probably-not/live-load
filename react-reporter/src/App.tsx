// Root component for the LiveLoad HTML reporter.
//
// Loads and parses the report data, then routes between two top-level views:
// - "compare" (default for ≥2 scenarios): multi-scenario comparison view
// - "scenario" (default for 1 scenario): per-scenario drill-down
//
// Routing is purely in-memory state — no URL changes — because the report
// is a single self-contained file with no router needed.

import { useCallback, useEffect, useMemo, useState } from "react";

import { ComparisonView } from "./components/CompareView";
import { ScenarioReport } from "./components/ScenarioView";
import { loadData } from "./data";
import { fmtTime } from "./format";
import { SCENARIO_COLORS } from "./meta";
import { parseScenario } from "./parse";
import type { ParsedScenario, ParsedScenarioEntry } from "./types";

type View = "compare" | "scenario";

export default function App() {
  const [scenarios, setScenarios] = useState<ParsedScenarioEntry[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  // Router state
  const [view, setView] = useState<View>("compare");
  const [activeIdx, setActiveIdx] = useState(0);
  const [activeNode, setActiveNode] = useState<string | null>(null);
  const [selectedIndices, setSelectedIndices] = useState<number[]>([]);

  // Load + parse report data on mount
  useEffect(() => {
    loadData()
      .then((raw) => {
        const parsed = raw.map(parseScenario);
        setScenarios(parsed);
        setSelectedIndices(parsed.map((_, i) => i));
        // Default view: drill straight into the only scenario when there's just one,
        // otherwise land on the comparison view
        if (parsed.length === 1) {
          setView("scenario");
          setActiveIdx(0);
        } else {
          setView("compare");
        }
      })
      .catch((e: Error) => setError(e.message));
  }, []);

  const colors = useMemo(() => {
    if (!scenarios) return [];
    return scenarios.map((_, i) => SCENARIO_COLORS[i % SCENARIO_COLORS.length]);
  }, [scenarios]);

  const drillIn = useCallback((idx: number) => {
    setActiveIdx(idx);
    setActiveNode(null);
    setView("scenario");
    window.scrollTo({ top: 0, behavior: "instant" });
  }, []);

  const backToCompare = useCallback(() => {
    setView("compare");
    setActiveNode(null);
    window.scrollTo({ top: 0, behavior: "instant" });
  }, []);

  if (error) {
    return (
      <div className="R">
        <div className="Ri">
          <div className="Ld" style={{ color: "var(--er)" }}>
            Failed to load data: {error}
          </div>
        </div>
      </div>
    );
  }

  if (!scenarios) {
    return (
      <div className="R">
        <div className="Ri">
          <div className="Ld">
            <span className="sp" />
            Loading report data...
          </div>
        </div>
      </div>
    );
  }

  // For the comparison view's filter, ensure we always have at least one scenario selected
  const indicesForCompare =
    selectedIndices.length > 0 ? selectedIndices : scenarios.map((_, i) => i);

  // Footer info — pulled from the first non-error scenario, since metadata is duplicated
  const firstOk = scenarios.find((s): s is ParsedScenario => !s.error);
  const footerVersion = firstOk?.version ?? "";
  const footerTime = firstOk?.generated_at ? fmtTime(firstOk.generated_at) : "";

  return (
    <div className="R">
      <div className="Ri">
        {view === "compare" ? (
          <ComparisonView
            scenarios={scenarios}
            indices={indicesForCompare}
            colors={colors}
            onDrillIn={drillIn}
            onChangeSelection={setSelectedIndices}
          />
        ) : scenarios[activeIdx].error ? (
          <>
            {scenarios.length > 1 && (
              <button className="Hbk" onClick={backToCompare}>
                ← Back to comparison
              </button>
            )}
            <div
              style={{
                background: "var(--erb)",
                border: "1px solid var(--er)",
                borderRadius: 8,
                padding: "32px 24px",
                textAlign: "center",
              }}
            >
              <div
                style={{
                  fontSize: 16,
                  fontWeight: 600,
                  color: "var(--er)",
                  marginBottom: 8,
                }}
              >
                Scenario Failed
              </div>
              <div
                style={{
                  fontFamily: "var(--mono)",
                  fontSize: 14,
                  color: "var(--t2)",
                }}
              >
                {scenarios[activeIdx].name}
              </div>
              <div
                style={{
                  fontFamily: "var(--mono)",
                  fontSize: 13,
                  color: "var(--t2)",
                  marginTop: 12,
                  background: "var(--s1)",
                  padding: "12px 16px",
                  borderRadius: 6,
                  display: "inline-block",
                  textAlign: "left",
                  maxWidth: "100%",
                  overflow: "auto",
                }}
              >
                {scenarios[activeIdx].reason}
              </div>
            </div>
          </>
        ) : (
          <ScenarioReport
            scenario={scenarios[activeIdx]}
            activeNode={activeNode}
            onSelectNode={setActiveNode}
            onBack={scenarios.length > 1 ? backToCompare : null}
          />
        )}

        <div className="Ft">
          LiveLoad{footerVersion ? ` ${footerVersion}` : ""}
          {footerTime ? ` — ${footerTime}` : ""}
        </div>
      </div>
    </div>
  );
}
