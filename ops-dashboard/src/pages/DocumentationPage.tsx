import { useCallback, useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import type { DocumentationRow } from "@/types/ops-dashboard";

export default function DocumentationPage() {
  const [docs, setDocs] = useState<DocumentationRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [docType, setDocType] = useState("");
  const [language, setLanguage] = useState("");

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    let q = supabase.from("documentation").select("*").eq("is_published", true).order("updated_at", { ascending: false });
    if (docType) q = q.eq("doc_type", docType);
    if (language) q = q.eq("language", language);
    const { data, error: err } = await q;
    if (err) setError(err.message);
    setDocs((data ?? []) as DocumentationRow[]);
    setLoading(false);
  }, [docType, language]);

  useEffect(() => { load(); }, [load]);

  return (
    <div>
      <h1 className="ops-title">Documentação</h1>
      <p className="ops-subtitle">Publicados com is_published = true</p>
      <div style={{ display: "flex", gap: 8, marginBottom: 16, flexWrap: "wrap" }}>
        <input className="ops-input" placeholder="doc_type" value={docType} onChange={(e) => setDocType(e.target.value)} />
        <input className="ops-input" placeholder="language" value={language} onChange={(e) => setLanguage(e.target.value)} />
        <button type="button" className="ops-btn" onClick={load} disabled={loading}>{loading ? "…" : "Filtrar"}</button>
      </div>
      {error && <p className="ops-error">{error}</p>}
      <section className="ops-card">
        {docs.length === 0 ? <p style={{ color: "var(--muted)" }}>Nenhum documento.</p> : docs.map((d) => (
          <article key={d.id} className="ops-list-item">
            <h3 style={{ margin: "0 0 6px" }}>{d.title}</h3>
            <p style={{ margin: 0, fontSize: 12, color: "var(--muted)" }}>
              {d.doc_type ?? "geral"} · {d.language} · {d.tags?.join(", ") || "sem tags"}
            </p>
            {d.body && <p style={{ marginTop: 8, fontSize: 13, whiteSpace: "pre-wrap" }}>{d.body.slice(0, 400)}{d.body.length > 400 ? "…" : ""}</p>}
          </article>
        ))}
      </section>
    </div>
  );
}
