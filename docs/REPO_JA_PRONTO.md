# O que já está feito no repositório (não precisas programar)

## App iOS (App Store)

| Item | Ficheiro |
|------|----------|
| Cadeia Valhalla → OSRM → MapKit → cache | `RoutingService.swift` |
| Aviso “rota via OSRM / restrições limitadas” | `RoutingService.swift`, `UtilitiesRegionalSettings.swift` |
| Modo “Apenas rotas seguras para caminhão” | `ViewsHorizonView.swift`, `HorizonSheets.swift` |
| Route Easy (3 opções de rota) | `ServicesRouteEasyEngine.swift`, `HorizonRouteEasyViews.swift` |
| Diagnostics (ping Valhalla, Supabase, etc.) | `ServicesIntegrationsHealthCheck.swift` |
| Guia App Store + fallbacks | `docs/APP_STORE_ROTAS.md` |

## AWS / Valhalla (infra)

| Item | Ficheiro |
|------|----------|
| Bootstrap EC2 Oregon | `backend/valhalla-production/aws-oregon-valhalla-bootstrap.sh` |
| Atalho no Mac | `backend/valhalla-production/run-bootstrap-from-mac.sh` |
| Instalar Valhalla + HTTPS | `backend/valhalla-production/deploy.sh` |
| Teardown | `backend/valhalla-production/aws-oregon-teardown.sh` |
| Verificar AWS CLI | `backend/valhalla-production/verificar-aws-cli.sh` |
| Copiar deploy para EC2 | `backend/valhalla-production/copiar-deploy-para-ec2.sh` |
| Guia completo Mac | `docs/DEPLOY_VALHALLA_DO_MAC.md` |
| **Checklist só para ti (AWS)** | `docs/AWS_TU_FAZES.md` |

## Supabase

| Item | Ficheiro |
|------|----------|
| Migrations ops / `truck_routing_config` | `supabase/migrations/` |
| Edge function health-check | `supabase/functions/health-check/` |
| Ops dashboard React | `ops-dashboard/` |

## O que só tu fazes (fora do código)

1. `aws configure` + `run-bootstrap-from-mac.sh`  
2. DNS A → IP da EC2  
3. SSH + `deploy.sh`  
4. `TruckerEasy.secrets.xcconfig` com URL HTTPS  
5. Teste iPhone em 4G  

Ver: **`docs/AWS_TU_FAZES.md`**
