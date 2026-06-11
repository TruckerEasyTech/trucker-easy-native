import { useMemo } from "react";
import type { UsageMetric } from "@/types/ops-dashboard";

type Props = {
  metrics: UsageMetric[];
  /** Mostrar só métricas cujo nome contém este texto (opcional) */
  nameFilter?: string;
  maxSeries?: number;
};

/**
 * Gráfico simples em barras — interface compatível com `usage_metrics`:
 * metric_name, metric_value, metric_unit, recorded_at
 */
export function MetricsChart({ metrics, nameFilter, maxSeries = 8 }: Props) {
  const series = useMemo(() => {
    const filtered = nameFilter
      ? metrics.filter((m) =>
          m.metric_name.toLowerCase().includes(nameFilter.toLowerCase()),
        )
      : metrics;

    const byName = new Map<string, UsageMetric>();
    for (const row of filtered) {
      const prev = byName.get(row.metric_name);
      if (!prev || new Date(row.recorded_at) > new Date(prev.recorded_at)) {
        byName.set(row.metric_name, row);
      }
    }

    return [...byName.values()]
      .sort((a, b) => b.metric_value - a.metric_value)
      .slice(0, maxSeries);
  }, [metrics, nameFilter, maxSeries]);

  const maxVal = Math.max(...series.map((s) => s.metric_value), 1);

  if (series.length === 0) {
    return (
      <p style={{ color: "var(--muted)", fontSize: 13, margin: 0 }}>
        Sem métricas em `usage_metrics` para exibir.
      </p>
    );
  }

  return (
    <div className="metrics-chart" style={{ display: "flex", flexDirection: "column", gap: 10 }}>
      {series.map((row) => {
        const pct = Math.round((row.metric_value / maxVal) * 100);
        return (
          <div key={row.id} style={{ display: "grid", gridTemplateColumns: "140px 1fr 72px", gap: 10, alignItems: "center" }}>
            <span style={{ fontSize: 12, color: "var(--muted)" }} title={row.metric_name}>
              {row.metric_name}
            </span>
            <div
              style={{
                height: 10,
                background: "var(--surface)",
                borderRadius: 4,
                overflow: "hidden",
              }}
            >
              <div
                style={{
                  width: `${pct}%`,
                  height: "100%",
                  background: "var(--gold)",
                  borderRadius: 4,
                }}
              />
            </div>
            <span style={{ fontSize: 12, textAlign: "right" }}>
              {row.metric_value.toLocaleString()}
              {row.metric_unit ? ` ${row.metric_unit}` : ""}
            </span>
          </div>
        );
      })}
    </div>
  );
}
