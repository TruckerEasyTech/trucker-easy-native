// POST /functions/v1/health-check
//
// Modos:
// 1) Utilizador (JWT no Authorization): uma empresa — grava health_checks com company_id do user.
// 2) Sistema (cron): header x-cron-secret = CRON_SECRET — service role, todas as empresas ativas.
//
// Cron Supabase (exemplo):
//   select net.http_post(
//     url := 'https://PROJECT.supabase.co/functions/v1/health-check',
//     headers := jsonb_build_object(
//       'Content-Type', 'application/json',
//       'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true),
//       'x-cron-secret', 'YOUR_CRON_SECRET'
//     ),
//     body := '{"source":"pg-cron","environment":"production","mode":"system"}'::jsonb
//   );

import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-cron-secret",
};

type HealthStatus = "ok" | "degraded" | "error";

type CheckResult = {
  status: HealthStatus;
  checks: Record<string, unknown>;
  elapsed_ms: number;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const started = Date.now();
  let source = "unknown";
  let environment = "production";
  let mode: "user" | "system" = "user";

  try {
    if (req.method === "POST") {
      const body = await req.json().catch(() => ({}));
      if (typeof body?.source === "string") source = body.source;
      if (typeof body?.environment === "string") environment = body.environment;
      if (body?.mode === "system") mode = "system";
    }
  } catch {
    // ignore
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const cronSecret = Deno.env.get("CRON_SECRET");

  if (!supabaseUrl || !serviceKey) {
    return json(
      {
        status: "error",
        message: "Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY",
        elapsed_ms: Date.now() - started,
      },
      500,
    );
  }

  const service = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false },
  });

  const cronHeader = req.headers.get("x-cron-secret");

  if (mode === "system") {
    if (!cronSecret) {
      return json(
        { status: "error", message: "CRON_SECRET not configured on Edge Function", elapsed_ms: Date.now() - started },
        500,
      );
    }
    if (!cronHeader || cronHeader !== cronSecret) {
      return json(
        { status: "error", message: "Invalid or missing x-cron-secret", elapsed_ms: Date.now() - started },
        401,
      );
    }
  }

  const isSystemCron = mode === "system";

  // --- Modo sistema (cron): sem JWT de utilizador ---
  if (isSystemCron) {
    const companies = await loadActiveCompanies(service);
    const results: Array<{
      company_id: string;
      company_name?: string;
      status: HealthStatus;
      elapsed_ms: number;
    }> = [];

    for (const company of companies) {
      const run = await runHealthProbe(service, environment, company.id);
      await persistHealthCheck(service, {
        environment,
        companyId: company.id,
        source: source === "unknown" ? "pg-cron" : source,
        overall: run.status,
        elapsed: run.elapsed_ms,
        checks: run.checks,
        mode: "system",
      });
      results.push({
        company_id: company.id,
        company_name: company.name,
        status: run.status,
        elapsed_ms: run.elapsed_ms,
      });
    }

    const anyError = results.some((r) => r.status === "error");
    const anyDegraded = results.some((r) => r.status === "degraded");

    return json({
      mode: "system",
      source,
      environment,
      companies_checked: results.length,
      results,
      status: anyError ? "error" : anyDegraded ? "degraded" : "ok",
      elapsed_ms: Date.now() - started,
    });
  }

  // --- Modo utilizador: exige JWT ---
  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return json(
      {
        status: "error",
        message:
          "Autenticação obrigatória. Para cron, use mode=system e header x-cron-secret.",
        elapsed_ms: Date.now() - started,
      },
      401,
    );
  }

  const userClient = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY") ?? serviceKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });

  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData?.user) {
    return json(
      {
        status: "error",
        message: userErr?.message ?? "JWT inválido ou expirado",
        elapsed_ms: Date.now() - started,
      },
      401,
    );
  }

  const companyId = await resolveCompanyId(service, userData.user);
  if (!companyId) {
    return json(
      {
        status: "error",
        message: "Utilizador sem company_id (perfil ou metadata)",
        elapsed_ms: Date.now() - started,
      },
      403,
    );
  }

  const run = await runHealthProbe(service, environment, companyId);
  await persistHealthCheck(service, {
    environment,
    companyId,
    source,
    overall: run.status,
    elapsed: run.elapsed_ms,
    checks: run.checks,
    mode: "user",
    userId: userData.user.id,
  });

  return json(
    {
      mode: "user",
      status: run.status,
      source,
      environment,
      company_id: companyId,
      checks: run.checks,
      elapsed_ms: run.elapsed_ms,
    },
    run.status === "error" ? 503 : 200,
  );
});

// ---------------------------------------------------------------------------
// Core probe (per company)
// ---------------------------------------------------------------------------

async function runHealthProbe(
  supabase: SupabaseClient,
  environment: string,
  companyId: string,
): Promise<CheckResult> {
  const started = Date.now();
  const checks: Record<string, unknown> = { company_id: companyId };

  const { error: dbErr } = await supabase.from("usage_metrics").select("id").limit(1);
  checks.database = dbErr ? { ok: false, error: dbErr.message } : { ok: true };

  let routingQuery = supabase
    .from("truck_routing_config")
    .select("config_key, config_value, updated_at, company_id")
    .eq("environment", environment)
    .eq("config_key", "valhalla_primary_url");

  routingQuery = routingQuery.eq("company_id", companyId);

  const { data: routingRow, error: routingErr } = await routingQuery.maybeSingle();

  checks.truck_routing_config = routingErr
    ? { ok: false, error: routingErr.message }
    : {
      ok: !!routingRow,
      updated_at: routingRow?.updated_at ?? null,
    };

  let valhallaUrl = extractValhallaUrl(routingRow?.config_value);

  if (!valhallaUrl) {
    const { data: fallback } = await supabase
      .from("truck_routing_config")
      .select("config_value")
      .eq("environment", environment)
      .eq("config_key", "valhalla_primary_url")
      .is("company_id", null)
      .maybeSingle();
    valhallaUrl = extractValhallaUrl(fallback?.config_value);
    if (valhallaUrl) checks.valhalla_config_source = "global_fallback";
  }

  if (valhallaUrl) {
    checks.valhalla = await probeValhalla(valhallaUrl);
  } else {
    checks.valhalla = { ok: false, skipped: true, reason: "no valhalla_primary_url" };
  }

  const dbOk = (checks.database as { ok?: boolean })?.ok === true;
  const routingOk = (checks.truck_routing_config as { ok?: boolean })?.ok === true;
  const valhallaOk = (checks.valhalla as { ok?: boolean })?.ok === true;

  const status: HealthStatus =
    dbOk && routingOk && valhallaOk ? "ok" : dbOk ? "degraded" : "error";

  return { status, checks, elapsed_ms: Date.now() - started };
}

function extractValhallaUrl(configValue: unknown): string | null {
  if (!configValue || typeof configValue !== "object") return null;
  const cv = configValue as Record<string, unknown>;
  if (typeof cv.url === "string") return cv.url;
  if (typeof cv.endpoint === "string") return cv.endpoint;
  return null;
}

async function probeValhalla(url: string): Promise<Record<string, unknown>> {
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 8000);
    const res = await fetch(url.replace(/\/$/, "") + "/status", {
      method: "GET",
      signal: controller.signal,
    });
    clearTimeout(timeout);
    return { ok: res.ok, status: res.status, url };
  } catch (e) {
    return {
      ok: false,
      url,
      error: e instanceof Error ? e.message : String(e),
    };
  }
}

// ---------------------------------------------------------------------------
// Companies + user company_id
// ---------------------------------------------------------------------------

type CompanyRow = { id: string; name?: string };

async function loadActiveCompanies(supabase: SupabaseClient): Promise<CompanyRow[]> {
  const { data, error } = await supabase
    .from("companies")
    .select("id, name")
    .eq("is_active", true);

  if (!error && data?.length) {
    return data as CompanyRow[];
  }

  // Fallback: empresas com config de roteamento
  const { data: configs } = await supabase
    .from("truck_routing_config")
    .select("company_id")
    .not("company_id", "is", null);

  const ids = [
    ...new Set(
      (configs ?? [])
        .map((r) => (r as { company_id?: string }).company_id)
        .filter((id): id is string => typeof id === "string" && id.length > 0),
    ),
  ];

  return ids.map((id) => ({ id }));
}

async function resolveCompanyId(
  service: SupabaseClient,
  user: { id: string; app_metadata?: Record<string, unknown>; user_metadata?: Record<string, unknown> },
): Promise<string | null> {
  const meta =
    (user.app_metadata?.company_id as string | undefined) ??
    (user.user_metadata?.company_id as string | undefined);
  if (meta) return meta;

  const { data: profile } = await service
    .from("profiles")
    .select("company_id")
    .eq("id", user.id)
    .maybeSingle();

  if (profile?.company_id) return profile.company_id as string;

  const { data: member } = await service
    .from("company_members")
    .select("company_id")
    .eq("user_id", user.id)
    .limit(1)
    .maybeSingle();

  return (member?.company_id as string | undefined) ?? null;
}

async function persistHealthCheck(
  service: SupabaseClient,
  opts: {
    environment: string;
    companyId: string;
    source: string;
    overall: HealthStatus;
    elapsed: number;
    checks: Record<string, unknown>;
    mode: "user" | "system";
    userId?: string;
  },
) {
  const { data: envRow } = await service
    .from("deployment_environments")
    .select("id")
    .eq("environment_name", opts.environment)
    .maybeSingle();

  const row: Record<string, unknown> = {
    check_name: "health-check-edge",
    status: opts.overall,
    response_ms: opts.elapsed,
    environment_id: envRow?.id ?? null,
    company_id: opts.companyId,
    details: {
      source: opts.source,
      mode: opts.mode,
      user_id: opts.userId ?? null,
      checks: opts.checks,
    },
  };

  const { data: inserted, error: insertErr } = await service
    .from("health_checks")
    .insert(row)
    .select("id")
    .maybeSingle();

  if (insertErr) {
    console.error("[health-check] health_checks insert failed:", insertErr.message);
    return;
  }

  await persistUsageMetrics(service, {
    environment: opts.environment,
    companyId: opts.companyId,
    source: opts.source,
    overall: opts.overall,
    elapsed: opts.elapsed,
    checks: opts.checks,
  });

  await maybeCreateHealthNotification(service, {
    environment: opts.environment,
    companyId: opts.companyId,
    overall: opts.overall,
    elapsed: opts.elapsed,
    checks: opts.checks,
    healthCheckId: (inserted as { id?: string } | null)?.id ?? null,
  });
}

async function persistUsageMetrics(
  service: SupabaseClient,
  opts: {
    environment: string;
    companyId: string;
    source: string;
    overall: HealthStatus;
    elapsed: number;
    checks: Record<string, unknown>;
  },
) {
  const valhallaOk = (opts.checks.valhalla as { ok?: boolean })?.ok === true;
  const statusScore = opts.overall === "ok" ? 1 : opts.overall === "degraded" ? 0.5 : 0;

  const rows = [
    {
      metric_name: "health_check_elapsed_ms",
      metric_value: opts.elapsed,
      metric_unit: "ms",
      environment: opts.environment,
      source: opts.source,
      company_id: opts.companyId,
      metadata: { overall: opts.overall },
    },
    {
      metric_name: "valhalla_reachable",
      metric_value: valhallaOk ? 1 : 0,
      metric_unit: "bool",
      environment: opts.environment,
      source: opts.source,
      company_id: opts.companyId,
      metadata: { valhalla: opts.checks.valhalla ?? null },
    },
    {
      metric_name: "health_status_score",
      metric_value: statusScore,
      metric_unit: "score",
      environment: opts.environment,
      source: opts.source,
      company_id: opts.companyId,
      metadata: { overall: opts.overall },
    },
  ];

  const { error } = await service.from("usage_metrics").insert(rows);
  if (error) {
    console.error("[health-check] usage_metrics insert failed:", error.message);
  }
}

async function maybeCreateHealthNotification(
  service: SupabaseClient,
  opts: {
    environment: string;
    companyId: string;
    overall: HealthStatus;
    elapsed: number;
    checks: Record<string, unknown>;
    healthCheckId: string | null;
  },
) {
  if (opts.overall === "ok") return;

  const since = new Date(Date.now() - 60 * 60 * 1000).toISOString();
  const { data: recent } = await service
    .from("notifications")
    .select("id")
    .eq("company_id", opts.companyId)
    .eq("source", "health-check")
    .eq("is_read", false)
    .gte("created_at", since)
    .limit(1);

  if (recent?.length) return;

  const valhalla = opts.checks.valhalla as Record<string, unknown> | undefined;
  const valhallaOk = valhalla?.ok === true;
  const severity = opts.overall === "error" ? "critical" : "warning";
  const title =
    opts.overall === "error"
      ? "Falha crítica de infraestrutura"
      : valhallaOk
      ? "Saúde degradada (roteamento)"
      : "Valhalla indisponível";

  const parts: string[] = [
    `Ambiente: ${opts.environment}`,
    `Tempo de resposta: ${opts.elapsed} ms`,
  ];
  if (!valhallaOk && valhalla) {
    const err = valhalla.error ?? valhalla.reason ?? valhalla.skipped;
    parts.push(`Valhalla: ${String(err ?? "não responde")}`);
  }

  const { error } = await service.from("notifications").insert({
    title,
    message: parts.join(" · "),
    severity,
    is_read: false,
    source: "health-check",
    company_id: opts.companyId,
    metadata: {
      health_check_id: opts.healthCheckId,
      overall: opts.overall,
      checks: opts.checks,
    },
  });

  if (error) {
    console.error("[health-check] notifications insert failed:", error.message);
  }
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
