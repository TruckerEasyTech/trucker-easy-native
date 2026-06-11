import { useCallback, useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import type { TruckRoutingConfigRow } from "@/types/ops-dashboard";

export default function RoutingConfigPage() {
  const [environment, setEnvironment] = useState("production");
  const [rows, setRows] = useState<TruckRoutingConfigRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    const { data, error: err } = await supabase
      .from("truck_routing_config")
      .select("*")
      .eq("environment", environment)
      .order("config_key", { ascending: true });
    if (err) setError(err.message);
    setRows((data ?? []) as TruckRoutingConfigRow[]);
    setLoading(false);
  }, [environment]);

  useEffect(() => { load(); }, [load]);

  return (
    <div>
      <h1 className="ops-title">Config de roteamento</h1>
      <p className="ops-subtitle">truck_routing_config por ambiente (Valhalla, flags)</p>
      <div style={{ display: "flex", gap: 8, marginBottom: 16 }}>
        <select className="ops-select" value={environment} onChange={(e) => setEnvironment(e.target.value)}>
          <option value="production">production</option>
          <option value="staging">staging</option>
          <option value="development">development</option>
        </select>
        <button type="button" className="ops-btn" onClick={load} disabled={loading}>{loading ? "…" : "Atualizar"}</button>
      </div>
      {error && <p className="ops-error">{error}</p>}
      <section className="ops-card">
        <table className="ops-table">
          <thead>
            <tr><th>Chave</th><th>Valor (JSON)</th><th>Atualizado</th></tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.id}>
                <td><code>{r.config_key}</code></td>
                <td><pre className="ops-pre" style={{ maxHeight: 120, margin: 0 }}>{JSON.stringify(r.config_value, null, 2)}</pre></td>
                <td>{new Date(r.updated_at).toLocaleString()}</td>
              </tr>
            ))}
          </tbody>
        </table>
        {rows.length === 0 && !loading && <p style={{ color: "var(--muted)" }}>Sem configs para este ambiente.</p>}
      </section>
    </div>
  );
}
