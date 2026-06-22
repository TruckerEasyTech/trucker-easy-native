// trip-share — Compartilhamento de viagem (acompanhamento read-only estilo Life360).
//
// O motorista (app) escreve a posição; a família abre o link no navegador e VÊ o caminhão
// ao vivo num mapa. NÃO é navegação: a página é só leitura, sem rota nem instruções.
//
//  POST  (do app, JSON {action,...})  → escreve via service role:
//        action "start"  : cria/retoma a viagem (token, driver_name, origin/dest), ativa, expira em 12h
//        action "update" : atualiza lat/lng/heading/speed (e renova a expiração)
//        action "stop"   : marca inativa (o link para de mostrar posição)
//  GET   ?t=<token>&json=1            → JSON da posição (só ativa + não expirada)
//  GET   ?t=<token>                   → página HTML de acompanhamento (Leaflet/OSM, sem chave)
//
//  Deploy:  supabase functions deploy trip-share --no-verify-jwt
//  (público: a família abre no navegador sem apikey; a escrita usa SERVICE_ROLE_KEY do ambiente)

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const REST = `${SUPABASE_URL}/rest/v1/live_trip_shares`;
const TABLE_TTL_HOURS = 12;

const cors: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

function svcHeaders(extra: Record<string, string> = {}): Record<string, string> {
  return {
    apikey: SERVICE_KEY,
    Authorization: `Bearer ${SERVICE_KEY}`,
    "Content-Type": "application/json",
    ...extra,
  };
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

function sanitizeToken(t: string | null): string | null {
  if (!t) return null;
  const clean = t.trim().toLowerCase();
  return /^[a-z0-9]{8,40}$/.test(clean) ? clean : null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  if (!SUPABASE_URL || !SERVICE_KEY) {
    return json({ error: "not_configured" }, 503);
  }

  const url = new URL(req.url);

  // ---- POST: escrita do app (service role) ----
  if (req.method === "POST") {
    let payload: Record<string, unknown>;
    try {
      payload = await req.json();
    } catch {
      return json({ error: "bad_json" }, 400);
    }
    const token = sanitizeToken(String(payload.token ?? ""));
    const action = String(payload.action ?? "");
    if (!token) return json({ error: "bad_token" }, 400);

    const nowISO = new Date().toISOString();
    const expISO = new Date(Date.now() + TABLE_TTL_HOURS * 3600_000).toISOString();

    if (action === "start") {
      const row: Record<string, unknown> = {
        token,
        driver_name: String(payload.driver_name ?? "Driver").slice(0, 80),
        active: true,
        started_at: nowISO,
        updated_at: nowISO,
        expires_at: expISO,
      };
      if (payload.origin_name) row.origin_name = String(payload.origin_name).slice(0, 200);
      if (payload.dest_name) row.dest_name = String(payload.dest_name).slice(0, 200);
      const r = await fetch(REST, {
        method: "POST",
        headers: svcHeaders({ Prefer: "resolution=merge-duplicates,return=minimal" }),
        body: JSON.stringify(row),
      });
      return r.ok ? json({ ok: true }) : json({ error: "start_failed" }, 502);
    }

    if (action === "update") {
      const patch: Record<string, unknown> = { updated_at: nowISO, expires_at: expISO, active: true };
      if (typeof payload.latitude === "number") patch.latitude = payload.latitude;
      if (typeof payload.longitude === "number") patch.longitude = payload.longitude;
      if (typeof payload.heading === "number") patch.heading = payload.heading;
      if (typeof payload.speed_mph === "number") patch.speed_mph = payload.speed_mph;
      const r = await fetch(`${REST}?token=eq.${token}`, {
        method: "PATCH",
        headers: svcHeaders({ Prefer: "return=minimal" }),
        body: JSON.stringify(patch),
      });
      return r.ok ? json({ ok: true }) : json({ error: "update_failed" }, 502);
    }

    if (action === "stop") {
      const r = await fetch(`${REST}?token=eq.${token}`, {
        method: "PATCH",
        headers: svcHeaders({ Prefer: "return=minimal" }),
        body: JSON.stringify({ active: false, updated_at: nowISO }),
      });
      return r.ok ? json({ ok: true }) : json({ error: "stop_failed" }, 502);
    }

    return json({ error: "bad_action" }, 400);
  }

  // ---- GET ----
  const token = sanitizeToken(url.searchParams.get("t"));
  const wantsJSON = url.searchParams.get("json") === "1";

  if (!token) {
    return wantsJSON ? json({ error: "bad_token" }, 400)
                     : new Response(notFoundHTML(), { status: 404, headers: htmlHeaders() });
  }

  // Busca a linha (só ativa e não expirada).
  const nowISO = new Date().toISOString();
  const q = `${REST}?token=eq.${token}&active=eq.true&expires_at=gt.${nowISO}` +
            `&select=driver_name,origin_name,dest_name,latitude,longitude,heading,speed_mph,updated_at`;
  const r = await fetch(q, { headers: svcHeaders() });
  const rows = r.ok ? await r.json() : [];
  const row = Array.isArray(rows) && rows.length > 0 ? rows[0] : null;

  if (wantsJSON) {
    return row ? json(row) : json({ error: "not_found_or_ended" }, 404);
  }

  // Página de acompanhamento (sempre devolve a página; ela busca o JSON e mostra o estado).
  return new Response(viewerHTML(token), { headers: htmlHeaders() });
});

function htmlHeaders(): Record<string, string> {
  return { ...cors, "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" };
}

function notFoundHTML(): string {
  return `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Trucker Easy</title></head><body style="font-family:-apple-system,sans-serif;background:#0f0f12;color:#fff;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;text-align:center">
<div><div style="font-size:42px">🚚</div><h2>Link inválido</h2><p style="color:#9aa">Esse link de viagem não é válido.</p></div></body></html>`;
}

function viewerHTML(token: string): string {
  return `<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<title>Trucker Easy — Viagem ao vivo</title>
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" crossorigin="">
<style>
  :root { --orange:#f57c17; }
  * { box-sizing:border-box; }
  html,body { margin:0; height:100%; font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif; background:#0f0f12; color:#fff; }
  #map { position:absolute; top:0; left:0; right:0; bottom:0; background:#0f0f12; }
  .card {
    position:absolute; left:12px; right:12px; bottom:12px; z-index:1000;
    background:rgba(15,15,18,.92); border:1px solid rgba(255,255,255,.08);
    border-radius:16px; padding:14px 16px; backdrop-filter:blur(8px);
    box-shadow:0 8px 30px rgba(0,0,0,.5);
  }
  .row { display:flex; align-items:center; gap:10px; }
  .live { width:9px; height:9px; border-radius:50%; background:#22c55e; box-shadow:0 0 0 0 rgba(34,197,94,.7); animation:pulse 1.8s infinite; }
  @keyframes pulse { 0%{box-shadow:0 0 0 0 rgba(34,197,94,.6)} 70%{box-shadow:0 0 0 10px rgba(34,197,94,0)} 100%{box-shadow:0 0 0 0 rgba(34,197,94,0)} }
  .name { font-weight:700; font-size:17px; }
  .meta { color:#9aa3ad; font-size:13px; margin-top:4px; }
  .badge { margin-left:auto; font-size:12px; color:#22c55e; font-weight:600; }
  .ended { color:#f59e0b; }
  .truck { font-size:11px; color:#777; margin-top:8px; }
  .truck b { color:var(--orange); }
  .pin { filter:drop-shadow(0 2px 3px rgba(0,0,0,.5)); }
</style>
</head>
<body>
<div id="map"></div>
<div class="card">
  <div class="row">
    <span class="live" id="dot"></span>
    <div>
      <div class="name" id="name">Carregando…</div>
      <div class="meta" id="meta">Buscando a posição do motorista…</div>
    </div>
    <span class="badge" id="badge">AO VIVO</span>
  </div>
  <div class="truck">Acompanhamento <b>Trucker Easy</b> · somente visualização</div>
</div>

<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js" crossorigin=""></script>
<script>
  const TOKEN = ${JSON.stringify(token)};
  const ENDPOINT = location.pathname + "?t=" + encodeURIComponent(TOKEN) + "&json=1";

  const map = L.map('map', { zoomControl:true, attributionControl:true }).setView([39.5, -98.35], 4);
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom: 19, attribution: '&copy; OpenStreetMap'
  }).addTo(map);

  function truckIcon(heading) {
    const h = (typeof heading === 'number' && isFinite(heading)) ? heading : 0;
    const svg =
      '<svg class="pin" width="40" height="40" viewBox="0 0 40 40" xmlns="http://www.w3.org/2000/svg" style="transform:rotate(' + h + 'deg)">' +
        '<g transform="translate(20,20)">' +
          '<rect x="-9" y="-16" width="18" height="32" rx="6" fill="#fff"/>' +
          '<rect x="-7.5" y="-14.5" width="15" height="29" rx="5" fill="#15161a"/>' +
          '<rect x="-7.5" y="-14.5" width="15" height="12" rx="5" fill="#f57c17"/>' +
          '<rect x="-5" y="-12.5" width="10" height="4" rx="2" fill="#a9cdf5"/>' +
        '</g>' +
      '</svg>';
    return L.divIcon({ html: svg, className: '', iconSize: [40,40], iconAnchor: [20,20] });
  }

  let marker = null, firstFix = true;

  function ago(iso) {
    const s = Math.max(0, Math.round((Date.now() - new Date(iso).getTime())/1000));
    if (s < 60) return 'há ' + s + 's';
    const m = Math.round(s/60);
    if (m < 60) return 'há ' + m + ' min';
    return 'há ' + Math.round(m/60) + 'h';
  }

  async function poll() {
    try {
      const res = await fetch(ENDPOINT, { cache:'no-store' });
      if (!res.ok) { ended(); return; }
      const d = await res.json();
      if (d.error) { ended(); return; }

      document.getElementById('name').textContent = d.driver_name || 'Motorista';
      const speed = (typeof d.speed_mph === 'number') ? Math.round(d.speed_mph) + ' mph' : '';
      const dest = d.dest_name ? ' → ' + d.dest_name : '';
      const upd = d.updated_at ? ('atualizado ' + ago(d.updated_at)) : '';
      document.getElementById('meta').textContent = [speed, dest].filter(Boolean).join(' · ') || upd;
      document.getElementById('badge').textContent = 'AO VIVO';
      document.getElementById('badge').className = 'badge';
      document.getElementById('dot').style.background = '#22c55e';

      if (typeof d.latitude === 'number' && typeof d.longitude === 'number') {
        const ll = [d.latitude, d.longitude];
        if (!marker) marker = L.marker(ll, { icon: truckIcon(d.heading) }).addTo(map);
        else { marker.setLatLng(ll); marker.setIcon(truckIcon(d.heading)); }
        if (firstFix) { map.setView(ll, 14); firstFix = false; }
        else map.panTo(ll, { animate:true });
      }
    } catch (_) { /* mantém último estado em falha de rede */ }
  }

  function ended() {
    document.getElementById('meta').textContent = 'A viagem foi encerrada pelo motorista.';
    document.getElementById('badge').textContent = 'ENCERRADA';
    document.getElementById('badge').className = 'badge ended';
    document.getElementById('dot').style.background = '#f59e0b';
  }

  poll();
  setInterval(poll, 5000);
</script>
</body>
</html>`;
}
