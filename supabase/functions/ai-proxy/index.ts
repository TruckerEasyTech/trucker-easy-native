// POST /functions/v1/ai-proxy
//
// Proxy seguro do OpenRouter (chat completions). A CHAVE fica NO SERVIDOR (secret OPENROUTER_API_KEY),
// nunca no app — antes a OpenRouterAPIKey embarcava no IPA e era extraível. O app chama esta função
// com a anon key do Supabase; a função injeta a chave real e repassa a resposta (incl. streaming SSE).
//
// Deploy:  supabase functions deploy ai-proxy --no-verify-jwt
// Secret:  supabase secrets set OPENROUTER_API_KEY=sk-or-...
//
// O corpo recebido é repassado VERBATIM ao OpenRouter (mesmo formato OpenAI que o app já envia).

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "method_not_allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const key = Deno.env.get("OPENROUTER_API_KEY");
  if (!key) {
    return new Response(JSON.stringify({ error: "proxy_not_configured" }), {
      status: 503,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const body = await req.text();
  const upstream = await fetch(OPENROUTER_URL, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${key}`,
      "Content-Type": "application/json",
      "X-Title": "Trucker Easy App",
      "HTTP-Referer": "https://truckereasy.com",
    },
    body,
  });

  // Repassa a resposta (stream SSE quando "stream": true) diretamente ao app.
  return new Response(upstream.body, {
    status: upstream.status,
    headers: {
      ...corsHeaders,
      "Content-Type": upstream.headers.get("Content-Type") ?? "text/event-stream",
    },
  });
});
