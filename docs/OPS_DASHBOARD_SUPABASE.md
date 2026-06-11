# Painel operacional — integração Supabase (schema real)

Migração aplicada em `truck_routing_config`:

- `environment` obrigatório, default `production`
- CHECK: `production` | `staging` | `development`
- Trigger `updated_at` automático
- Unicidade por `(config_key, environment)` (não só `config_key`)
- Índices para filtros

SQL versionado: `supabase/migrations/20260516000000_truck_routing_ops_dashboard.sql`

---

## 1) Monitoramento

**Tabelas:** `usage_metrics` + `health_checks` (não usar `system_metrics`).

```ts
const [{ data: m }, { data: h }] = await Promise.all([
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
```

`MetricsChart`: campos `metric_name`, `metric_value`, `metric_unit`, `recorded_at`.

---

## 2) Alertas

**Tabela:** `notifications` (não `alerts`).

| UI antiga   | Campo real   |
|------------|--------------|
| title      | `title`      |
| body       | `message`    |
| severity   | `severity`   |
| acknowledged | `is_read` |

```ts
const { data } = await supabase
  .from("notifications")
  .select("*")
  .order("created_at", { ascending: false });

await supabase
  .from("notifications")
  .update({ is_read: true })
  .eq("id", id);
```

---

## 3) Documentação

**Tabela:** `documentation`

```ts
const { data } = await supabase
  .from("documentation")
  .select("*")
  .eq("is_published", true)
  .order("updated_at", { ascending: false });
```

Filtros opcionais: `.eq("doc_type", ...)`, `.contains("tags", [...])`, `.eq("language", "pt")`.

---

## 4) health-check — métricas e alertas automáticos

Após cada probe, a edge function `health-check`:

1. Insere em `health_checks` (como antes).
2. Insere em `usage_metrics`: `health_check_elapsed_ms`, `valhalla_reachable`, `health_status_score`.
3. Se status `degraded` ou `error`, insere em `notifications` (máx. 1 alerta não lido por empresa por hora, `source: health-check`).

**Deploy:** `supabase functions deploy health-check`

**Realtime (dashboard):** migration `20260519100000_ops_realtime_publication.sql` — ativa publication em `health_checks`, `notifications`, `usage_metrics`.

---

## 5) API de teste (health-check + ops-feed)

Edge Function: `supabase/functions/health-check/index.ts`

```ts
const { data, error } = await supabase.functions.invoke("health-check", {
  body: { source: "api-test-page", environment: "production" },
});
```

Deploy + secret para cron:

```bash
supabase secrets set CRON_SECRET="$(openssl rand -hex 32)"
supabase functions deploy health-check --project-ref YOUR_PROJECT_REF
```

**Dois modos:**

| Modo | Quem chama | Como |
|------|------------|------|
| **user** | Botão no `/ops/api-teste` (logado) | `Authorization: Bearer <JWT utilizador>` |
| **system** | Cron (pg_cron / scheduled) | Body `{ "mode": "system", "environment": "production" }` + header `x-cron-secret: <CRON_SECRET>` |

O cron **não** deve usar só anon key — sem JWT de user o modo user falha de propósito. O modo system usa service role na função e grava `health_checks` por cada empresa em `companies` com `is_active = true`.

**Fallback** (sem Edge Function): `select id from usage_metrics limit 1` + leitura de `truck_routing_config` para `valhalla_primary_url`.

---

## Config de roteamento (exemplo)

```sql
insert into truck_routing_config (config_key, config_value, environment, description)
values (
  'valhalla_primary_url',
  '{"url": "https://valhalla.seudominio.com"}'::jsonb,
  'production',
  'Valhalla truck costing — HTTPS'
)
on conflict (config_key, environment) do update
  set config_value = excluded.config_value,
      description = excluded.description;
```

---

## Páginas React prontas

Código completo em **`ops-dashboard/`** (Vite + React + TypeScript):

- `MonitoringPage.tsx` — `usage_metrics` + `health_checks`
- `AlertsPage.tsx` — `notifications` (`is_read`)
- `DocumentationPage.tsx` — `documentation`
- `ApiTestPage.tsx` — `health-check` + fallback
- `RoutingConfigPage.tsx` — `truck_routing_config` por `environment`

Ver `ops-dashboard/README.md` para copiar no Lovable.

## Status do painel

Com estas tabelas e a função `health-check`, o dashboard cobre monitoramento, alertas, documentação e teste de API de forma alinhada ao schema de produção.
