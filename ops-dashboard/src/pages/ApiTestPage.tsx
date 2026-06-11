import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import type { HealthCheckInvokeResult } from "@/types/ops-dashboard";

export default function ApiTestPage() {
  const [environment, setEnvironment] = useState("production");
  const [lat, setLat] = useState("40.7128");
  const [lon, setLon] = useState("-74.0060");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<HealthCheckInvokeResult | null>(null);
  const [opsFeedResult, setOpsFeedResult] = useState<unknown>(null);
  const [fallback, setFallback] = useState<Record<string, unknown> | null>(null);

  async function runEdgeFunction() {
    setLoading(true);
    setError(null);
    setResult(null);
    setOpsFeedResult(null);
    const { data, error: fnErr } = await supabase.functions.invoke("health-check", {
      body: { source: "api-test-page", environment },
    });
    if (fnErr) {
      setError(fnErr.message);
      await runFallback();
    } else {
      setResult((data ?? null) as HealthCheckInvokeResult);
    }
    setLoading(false);
  }

  async function runOpsFeed() {
    setLoading(true);
    setError(null);
    setOpsFeedResult(null);
    const query = new URLSearchParams({
      lat,
      lon,
      radius_km: "50",
    });
    const { data, error: fnErr } = await supabase.functions.invoke(`ops-feed?${query.toString()}`, {
      method: "GET",
    });
    if (fnErr) {
      setError(fnErr.message);
    } else {
      setOpsFeedResult(data);
    }
    setLoading(false);
  }

  async function runFallback() {
    const [{ data: ping }, { data: cfg }] = await Promise.all([
      supabase.from("usage_metrics").select("id").limit(1),
      supabase
        .from("truck_routing_config")
        .select("config_key, config_value, environment, updated_at")
        .eq("environment", environment)
        .eq("config_key", "valhalla_primary_url")
        .maybeSingle(),
    ]);
    setFallback({ database_ping: !!ping, valhalla_config: cfg ?? null });
  }

  return (
    <div>
      <h1 className="ops-title">API de teste</h1>
      <p className="ops-subtitle">
        Invoca edge functions: health-check (grava health_checks, usage_metrics e alertas) e ops-feed (app iOS)
      </p>
      <div style={{ display: "flex", gap: 8, marginBottom: 16, flexWrap: "wrap", alignItems: "center" }}>
        <select className="ops-select" value={environment} onChange={(e) => setEnvironment(e.target.value)}>
          <option value="production">production</option>
          <option value="staging">staging</option>
          <option value="development">development</option>
        </select>
        <button type="button" className="ops-btn" onClick={runEdgeFunction} disabled={loading}>
          {loading ? "A testar…" : "Executar health-check"}
        </button>
        <button type="button" className="ops-btn ops-btn-secondary" onClick={runFallback} disabled={loading}>
          Fallback DB
        </button>
      </div>

      <div style={{ display: "flex", gap: 8, marginBottom: 16, flexWrap: "wrap", alignItems: "center" }}>
        <label style={{ fontSize: 13, color: "var(--muted)" }}>
          ops-feed lat
          <input
            className="ops-select"
            style={{ marginLeft: 6, width: 100 }}
            value={lat}
            onChange={(e) => setLat(e.target.value)}
          />
        </label>
        <label style={{ fontSize: 13, color: "var(--muted)" }}>
          lon
          <input
            className="ops-select"
            style={{ marginLeft: 6, width: 100 }}
            value={lon}
            onChange={(e) => setLon(e.target.value)}
          />
        </label>
        <button type="button" className="ops-btn ops-btn-secondary" onClick={runOpsFeed} disabled={loading}>
          Testar ops-feed
        </button>
      </div>

      {error && <p className="ops-error">{error}</p>}
      {result && (
        <section className="ops-card">
          <h2 style={{ fontSize: 14, color: "var(--gold)", marginTop: 0 }}>health-check</h2>
          <p>
            Status:{" "}
            <span
              className={`ops-badge ops-badge-${result.status === "ok" ? "ok" : result.status === "degraded" ? "warn" : "error"}`}
            >
              {result.status}
            </span>
            {result.elapsed_ms != null && ` · ${result.elapsed_ms} ms`}
          </p>
          <pre className="ops-pre">{JSON.stringify(result, null, 2)}</pre>
        </section>
      )}
      {opsFeedResult != null && (
        <section className="ops-card">
          <h2 style={{ fontSize: 14, color: "var(--gold)", marginTop: 0 }}>ops-feed</h2>
          <pre className="ops-pre">{JSON.stringify(opsFeedResult, null, 2)}</pre>
        </section>
      )}
      {fallback && (
        <section className="ops-card">
          <h2 style={{ fontSize: 14, color: "var(--gold)" }}>Fallback (sem Edge Function)</h2>
          <pre className="ops-pre">{JSON.stringify(fallback, null, 2)}</pre>
        </section>
      )}
    </div>
  );
}
