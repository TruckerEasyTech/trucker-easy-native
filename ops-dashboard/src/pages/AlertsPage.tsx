import { useCallback, useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useOpsRealtime } from "@/hooks/useOpsRealtime";
import type { NotificationRow } from "@/types/ops-dashboard";

function severityClass(severity: string) {
  const s = severity.toLowerCase();
  if (s === "critical" || s === "error") return "ops-badge ops-badge-error";
  if (s === "warning" || s === "warn") return "ops-badge ops-badge-warn";
  return "ops-badge ops-badge-ok";
}

export default function AlertsPage() {
  const [items, setItems] = useState<NotificationRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [filter, setFilter] = useState<"all" | "unread">("all");

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    let q = supabase.from("notifications").select("*").order("created_at", { ascending: false }).limit(200);
    if (filter === "unread") q = q.eq("is_read", false);
    const { data, error: err } = await q;
    if (err) setError(err.message);
    setItems((data ?? []) as NotificationRow[]);
    setLoading(false);
  }, [filter]);

  useEffect(() => { load(); }, [load]);

  async function markRead(id: string) {
    const { error: err } = await supabase.from("notifications").update({ is_read: true }).eq("id", id);
    if (err) { setError(err.message); return; }
    setItems((prev) => prev.map((n) => (n.id === id ? { ...n, is_read: true } : n)));
  }

  return (
    <div>
      <h1 className="ops-title">Alertas</h1>
      <p className="ops-subtitle">
        Alertas automáticos quando health-check reporta degraded/error (source: health-check)
      </p>
      <div style={{ display: "flex", gap: 8, marginBottom: 16, flexWrap: "wrap" }}>
        <select className="ops-select" value={filter} onChange={(e) => setFilter(e.target.value as "all" | "unread")}>
          <option value="all">Todos</option>
          <option value="unread">Não lidos</option>
        </select>
        <button type="button" className="ops-btn" onClick={load} disabled={loading}>{loading ? "…" : "Atualizar"}</button>
      </div>
      {error && <p className="ops-error">{error}</p>}
      <section className="ops-card">
        {items.length === 0 ? (
          <p style={{ color: "var(--muted)" }}>Sem notificações.</p>
        ) : (
          items.map((n) => (
            <article key={n.id} className="ops-list-item" style={{ opacity: n.is_read ? 0.65 : 1 }}>
              <div style={{ display: "flex", justifyContent: "space-between", gap: 12 }}>
                <div>
                  <div style={{ display: "flex", gap: 8, alignItems: "center", marginBottom: 4 }}>
                    <span className={severityClass(n.severity)}>{n.severity}</span>
                    {n.is_read && <span style={{ fontSize: 11, color: "var(--muted)" }}>lido</span>}
                  </div>
                  <h3 style={{ margin: "0 0 4px", fontSize: 15 }}>{n.title}</h3>
                  {n.message && <p style={{ margin: 0, fontSize: 13, color: "var(--muted)" }}>{n.message}</p>}
                  <p style={{ margin: "8px 0 0", fontSize: 11, color: "var(--muted)" }}>{new Date(n.created_at).toLocaleString()}</p>
                </div>
                {!n.is_read && (
                  <button type="button" className="ops-btn ops-btn-secondary" onClick={() => markRead(n.id)}>Marcar lido</button>
                )}
              </div>
            </article>
          ))
        )}
      </section>
    </div>
  );
}
