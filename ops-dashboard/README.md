# Ops Dashboard — Trucker Easy

Painel React/TypeScript alinhado ao schema Supabase real (`usage_metrics`, `health_checks`, `notifications`, `documentation`, `truck_routing_config`).

## Executar localmente

```bash
cd ops-dashboard
cp .env.example .env
# Edite VITE_SUPABASE_URL e VITE_SUPABASE_ANON_KEY
npm install
npm run dev
```

## Copiar para o projeto Lovable / Vite existente

| Origem (este repo) | Destino no seu dashboard |
|--------------------|---------------------------|
| `src/pages/MonitoringPage.tsx` | `src/pages/MonitoringPage.tsx` |
| `src/pages/AlertsPage.tsx` | `src/pages/AlertsPage.tsx` |
| `src/pages/DocumentationPage.tsx` | `src/pages/DocumentationPage.tsx` |
| `src/pages/ApiTestPage.tsx` | `src/pages/ApiTestPage.tsx` |
| `src/pages/RoutingConfigPage.tsx` | `src/pages/RoutingConfigPage.tsx` |
| `src/components/MetricsChart.tsx` | `src/components/MetricsChart.tsx` |
| `src/types/ops-dashboard.ts` | `src/types/ops-dashboard.ts` |
| `src/integrations/supabase/client.ts` | já existe — mantenha o seu client, só importe `supabase` |

### Substituições obrigatórias no código antigo

| Antes (errado) | Depois (correto) |
|----------------|------------------|
| `.from('system_metrics')` | `.from('usage_metrics')` |
| `.from('alerts')` | `.from('notifications')` |
| `acknowledged` | `is_read` |
| alert `body` | `message` |

### Rotas (exemplo em `App.tsx`)

```tsx
<Route path="/" element={<MonitoringPage />} />
<Route path="/alertas" element={<AlertsPage />} />
<Route path="/documentacao" element={<DocumentationPage />} />
<Route path="/api-teste" element={<ApiTestPage />} />
<Route path="/roteamento" element={<RoutingConfigPage />} />
```

### Edge Function

Deploy: `supabase functions deploy health-check` (ver `../supabase/functions/health-check/`).

Após deploy, cada execução do health-check também grava `usage_metrics` e cria `notifications` quando Valhalla/infra está degraded ou error.

### Realtime

Copiar `src/hooks/useOpsRealtime.ts` e usar em Monitoring/Alerts (já ligado no repo de referência).

Aplicar migration: `supabase/migrations/20260519100000_ops_realtime_publication.sql`

### Ficheiros novos no repo de referência

| Ficheiro | Função |
|----------|--------|
| `src/hooks/useOpsRealtime.ts` | Subscrição postgres_changes |
| `supabase/functions/health-check/index.ts` | Métricas + alertas automáticos |

### RLS

Garanta políticas `select` (e `update` em `notifications`) para utilizadores autenticados do painel, ou use service role só no backend — nunca no browser público.
