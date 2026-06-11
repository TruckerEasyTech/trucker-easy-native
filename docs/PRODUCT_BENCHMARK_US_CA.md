# Trucker Easy — Benchmark US/CA (Trucker Path × HERE)

Referência para paridade de produto em **rotas de caminhão** nos EUA e Canadá.

## Trucker Path ([truckerpath.com](https://truckerpath.com/trucker-path-app))

| Capacidade | Trucker Path | Trucker Easy hoje | Gap |
|------------|--------------|-------------------|-----|
| Perfil camião (altura, peso, eixos, reboques, hazmat) | ✅ Core | ✅ `TruckProfile` + `ComplianceRegulationProfile` | Hazmat/tunnel rules parcial |
| Rotas truck-safe (pontes baixas, peso) | ✅ Proprietário | ✅ Valhalla `truck` costing | Depende de tiles/região |
| Turn-by-turn + voz | ✅ | ✅ `NavigationEngine` + voz | — |
| Weigh station open/closed | ✅ + previsão (Diamond) | ✅ crowd + gov POI | Previsão ML fraca |
| Truck stops + parking | ✅ + previsão | ✅ Supabase + operational feeds | Previsão parking |
| Fuel prices / otimização rota | ✅ Diamond | ✅ parcial (`FuelPriceService`) | Otimização combustível |
| Offline maps | ✅ Gold/Diamond | ❌ | **Alto** |
| HOS trip planning | ✅ Diamond | ⚠️ timer local (`DotHOS`) — não ELD | ELD integration |
| Low clearance alerts | ✅ | ⚠️ `RouteWarningEngine` | Dados estruturados US |
| Night mode | ✅ | ✅ Mapbox dark / UI | — |
| Load board | ✅ | ❌ dispatch off | Opcional |

## HERE WeGo Pro / Routing v8 ([here.com](https://www.here.com/products/wego-pro))

| Capacidade | HERE | Trucker Easy hoje | Gap |
|------------|------|-------------------|-----|
| Rede rodoviária truck-specific | ✅ global | ✅ Valhalla OSM + costing | Cobertura ≠ HERE |
| Restrições tempo-dependentes | ✅ | ⚠️ limitado | — |
| U-turn avoidance | ✅ `avoid[features]=uTurns` | ⚠️ Valhalla `use_roads` | Configurável |
| Lista de restrições na rota | ✅ notices | ✅ `TruckRouteNotice` | UX de alertas |
| Offline regional | ✅ download | ❌ | **Alto** |
| Fleet / dispatch integration | ✅ Tour Planning | ⚠️ scaffold | — |
| ETA truck speed profiles | ✅ | ✅ Valhalla duration | — |

## Arquitetura Trucker Easy (diferencial)

- **Valhalla** = geometria na estrada (polyline, manobras).
- **Middleware quantum/TSP** = ordem de paradas (opcional; não substitui Valhalla).
- **Supabase** = POI, weigh crowd, parking signals.
- **Mapbox** = renderização; **MapKit** fallback.

## Roadmap sugerido (paridade comercial)

1. **P0 — Produção US/CA**: Valhalla NA tiles (Geofabrik `north-america/us`, `canada`) + HTTPS público; zero rotas emergency; reroute com aviso ao motorista.
2. **P1 — Confiança**: alertas estruturados low bridge / weight na rota; violações com severidade (estilo HERE notices).
3. **P2 — Retenção**: offline tiles região; weigh/parking prediction simples (histórico Supabase).
4. **P3 — Premium**: fuel-smart Route Easy; HOS-aware stop order (sem substituir ELD legal).
