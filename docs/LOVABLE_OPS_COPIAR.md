# Copiar para o Lovable — ops dashboard (prioridades 1, 2, 5)

## 1. Supabase (obrigatório)

```bash
cd "/Users/thaiskeller/Desktop/trucker easy app"
supabase db push
# ou colar SQL da migration no SQL Editor:
# supabase/migrations/20260519100000_ops_realtime_publication.sql

supabase functions deploy health-check
```

## 2. Ficheiros a sincronizar no Lovable

| Repo | Lovable |
|------|---------|
| `ops-dashboard/src/hooks/useOpsRealtime.ts` | `src/hooks/useOpsRealtime.ts` |
| `ops-dashboard/src/pages/MonitoringPage.tsx` | substituir |
| `ops-dashboard/src/pages/AlertsPage.tsx` | substituir |
| `ops-dashboard/src/pages/ApiTestPage.tsx` | substituir |
| `supabase/functions/health-check/index.ts` | deploy (não copiar para Vite) |

## 3. O que passa a funcionar

- **Alertas:** Valhalla down → linha em `notifications` (critical/warning).
- **Gráfico:** `usage_metrics` preenchido a cada health-check.
- **Monitoramento / Alertas:** atualizam sozinhos (Realtime).
- **API teste:** botões health-check + ops-feed.

## 4. Ainda no Lovable (manual)

- **ProtectedRoute** em `/ops/*` (auth + role admin).
- **CRUD** em RoutingConfig / Documentation (fase 2).

## 5. Testar

1. `/ops/api-teste` → Executar health-check (com Valhalla down deve criar alerta).
2. `/ops/alertas` → ver notificação sem F5.
3. `/ops` → gráfico com barras após alguns checks.

Cron system (15 min): ver `backend/valhalla-production/RODAR_AGORA.md` secção 9.
