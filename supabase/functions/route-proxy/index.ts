// Supabase Edge Function: POST /functions/v1/route-proxy/v1/optimize
//
// Purpose:
// - iOS calls this HTTPS endpoint, satisfying ATS.
// - The private/HTTP optimization backend stays server-side.
// - The upstream X-API-Key, if any, is stored as a Supabase secret, not in the app.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const upstreamBase = (Deno.env.get("ROUTE_OPTIMIZATION_UPSTREAM_URL") ?? "").trim().replace(/\/+$/, "");
  const upstreamKey = (Deno.env.get("ROUTE_OPTIMIZATION_UPSTREAM_API_KEY") ?? "").trim();

  if (!supabaseUrl || !anonKey) {
    return json({ error: "Missing Supabase function auth config" }, 500);
  }
  if (!upstreamBase) {
    return json({ error: "ROUTE_OPTIMIZATION_UPSTREAM_URL is not configured" }, 503);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return json({ error: "Authentication required" }, 401);
  }

  const supabase = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData?.user) {
    return json({ error: "Invalid or expired user session" }, 401);
  }

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const upstreamURL = `${upstreamBase}/v1/optimize`;
  const upstreamHeaders: Record<string, string> = {
    "Content-Type": "application/json",
    "Accept": "application/json",
  };
  if (upstreamKey) {
    upstreamHeaders["X-API-Key"] = upstreamKey;
  }

  try {
    const upstream = await fetch(upstreamURL, {
      method: "POST",
      headers: upstreamHeaders,
      body: JSON.stringify(body),
    });

    const text = await upstream.text();
    return new Response(text, {
      status: upstream.status,
      headers: {
        ...corsHeaders,
        "Content-Type": upstream.headers.get("Content-Type") ?? "application/json",
        "Cache-Control": "no-store",
      },
    });
  } catch (error) {
    return json(
      {
        error: "Route optimization upstream unavailable",
        detail: error instanceof Error ? error.message : String(error),
      },
      502,
    );
  }
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
}
