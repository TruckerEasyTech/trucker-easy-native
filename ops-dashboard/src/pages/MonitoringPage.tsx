import { useCallback, useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { MetricsChart } from "@/components/MetricsChart";
import { useOpsRealtime } from "@/hooks/useOpsRealtime";
import type { HealthCheck, UsageMetric } from "@/types/ops-dashboard";

function statusBadge(status: string) {
  const s = status.toLowerCase();
  if (s === "ok" || s === "healthy") return "ops-badge ops-badge-ok";
  if (s === "degraded" || s === "warn" || s === "warning") return "ops-badge ops-badge-warn";
  return "ops-badge ops-badge-error";
}

export default function MonitoringPage() {
  const [metrics, setMetrics] = useState<UsageMetric[]>([]);
  const [health, setHealth] = useState<HealthCheck[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    const [{ data: m, error: mErr }, { data: h, error: hErr }] = await Promise.all([
      supabase
        .from("usage_metrics")
        .select("*")
        .order("recorded_at", { ascending: false })
        .limit(1000),
      supabase
        .from("health_checks")
        .select("*, deployment_environments(environment_name)")
        .order("checked_at", { ascending: false })
        .limit(200),
    ]);

    if (mErr) setError(mErr.message);
    else if (hErr) setError(hErr.message);
    setMetrics((m ?? []) as UsageMetric[]);
    setHealth((h ?? []) as HealthCheck[]);
    setLoading(false);
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  useOpsRealtime(["usage_metrics", "health_checks"], load);

  return (
    <div>
      <h1 className="ops-title">Monitoramento</h1>
      <p className="ops-subtitle">
        Métricas em <code>usage_metrics</code> e saúde em <code>health_checks</code> (atualização automática via Realtime)
      </p>

      <div style={{ marginBottom: 16 }}>
        <button type="button" className="ops-btn" onClick={load} disabled={loading}>
          {loading ? "A carregar…" : "Atualizar"}
        </button>
      </div>

      {error && <p className="ops-error">{error}</p>}

      <div className="ops-grid-2">
        <section className="ops-card">
          <h2 style={{ fontSize: 14, margin: "0 0 12px", color: "var(--gold)" }}>Métricas</h2>
          <MetricsChart metrics={metrics} />
        </section>

        <section className="ops-card">
          <h2 style={{ fontSize: 14, margin: "0 0 12px", color: "var(--gold)" }}>Últimos health checks</h2>
          {health.length === 0 ? (
            <p style={{ color: "var(--muted)", fontSize: 13 }}>Nenhum registo.</p>
          ) : (
            <table className="ops-table">
              <thead>
                <tr>
                  <th>Check</th>
                  <th>Status</th>
                  <th>Env</th>
                  <th>ms</th>
                  <th>Quando</th>
                </tr>
              </thead>
              <tbody>
                {health.slice(0, 15).map((row) => (
                  <tr key={row.id}>
                    <td>{row.check_name}</td>
                    <td>
                      <span className={statusBadge(row.status)}>{row.status}</span>
                    </td>
                    <td>{row.deployment_environments?.environment_name ?? "—"}</td>
                    <td>{row.response_ms ?? "—"}</td>
                    <td>{new Date(row.checked_at).toLocaleString()}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </section>
      </div>
    </div>
  );
}
