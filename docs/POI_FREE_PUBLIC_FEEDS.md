# Feeds públicos gratuitos — Trucker Easy (EUA + Canadá)

**Road511, NextBillion e HERE são opcionais e pagos.** Esta stack usa só fontes abertas.

## Stack recomendada ($0)

| Fonte | Região | Dados | Live? | Custo |
|-------|--------|-------|-------|-------|
| **OSM Overpass** | US + CA | truck stop, fuel, shower, weigh (tag) | Estático (ingest) | $0 |
| **USDOT NTAD** | EUA | Jason's Law parking + WIM localização | Semanal | $0 |
| **Caltrans CVEF** | California | Balanças oficiais CHP | Estático | $0 |
| **Ontario 511** | Ontario | Inspeção CVSE + truck rest + ONroute | **Real-time** | $0 |
| **BC Open511** | BC | Eventos, obras, condições | Real-time | $0 |
| **Alberta 511** | AB | Condições, câmaras | Real-time | $0 |
| **Ohio OHGO** | OH | Truck parking `Open` | Real-time (registo grátis) | $0 |
| **TPIMS** | Corredor I-10 | Parking dinâmico | Real-time | $0 |
| **Crowd Supabase** | Global | Balança open/closed | Imediato | $0 |

## GitHub / specs úteis

- [open511/Open511API](https://github.com/open511/Open511API) — standard Open511 (BC, SF, etc.)
- [bcgov/api-specs](https://github.com/bcgov/api-specs) — specs BC gov APIs
- [infil00p/DriveBC_MCP](https://github.com/infil00p/DriveBC_MCP) — exemplo DriveBC `api.open511.gov.bc.ca`
- [jslightham/road-conditions](https://github.com/jslightham/road-conditions) — scrape 511on.ca câmaras

## Ontario 511 (Canadá — inspeção + parking)

Licença: [Open Government Licence](http://511on.ca/developers/resources)

```bash
# Inspeção CVSE (localização — open/closed via sinalização na estrada)
curl "https://511on.ca/api/v2/get/inspectionstations?format=json"

# Truck rest + Status Open/Closed + TruckParking Y/N
curl "https://511on.ca/api/v2/get/truckrestareas?format=json"

# ONroute service centres + CommercialParking count
curl "https://511on.ca/api/v2/get/servicecentres?format=json"
```

Limite: **10 pedidos / 60 s** — usar cron a cada 5–10 min, não por motorista.

## BC CVSE (Colúmbia Britânica — inspeção)

Lista oficial: [cvse.ca/inspection_stations.htm](https://www.cvse.ca/inspection_stations.htm)

- **Weigh2GoBC** não tem API pública de open/closed (programa transponder).
- Ingest: `gov/bc_cvse_stations.json` + sinal `monitoring` em `poi_operational_status`.
- TransLink GeoJSON (`trp.regionalroads.com`) estava instável (HTTP 500) — usamos lista CVSE curada.

## California weigh (Caltrans)

ArcGIS REST público:

```
https://caltrans-gis.dot.ca.gov/arcgis/rest/services/CHhighway/Vehicle_Enforcement_Facilities/MapServer/0/query?where=1=1&outFields=*&returnGeometry=true&outSR=4326&f=geojson
```

Sem open/closed live — localização oficial CHP.

## EUA nacional (NTAD)

Já no repo: `backend/government-poi-ingest/ingest_ntad.py`

ArcGIS USDOT: WIM + Jason's Law parking.

## Road511 — activo no Supabase (chave já configurada)

- **Onde:** Supabase → Edge Functions → Secrets → `ROAD511_API_KEY` + `ENABLE_ROAD511=true`
- **App:** `ops-feed` e `trucking-poi-feed` (não vai no xcconfig do iPhone)
- **Persist DB:** `bash scripts/sync_road511_corridors.sh` no EC2 ou Mac (com `SUPABASE_ANON_KEY` no `.env`)
- Plano Free: máx. 2 jurisdições por pedido (auto-detect no código); trial 14 dias

## Cron EC2 (recomendado)

```bash
*/10 * * * * /home/ubuntu/trucker-easy-app/scripts/run_government_poi_sync.sh >> /home/ubuntu/logs/truckereasy-gov-poi.log 2>&1
```

Log em `/var/log/` exige root — use `~/logs/` com o user `ubuntu`.

## Prioridade no app

1. `poi_operational_status` (Ontario 511, OHGO, TPIMS sync)
2. `places_near` gov fields (NTAD, OSM, on511, caltrans)
3. Crowd `weigh_station_reports`

Balanca open/closed **não existe API federal gratuita** — Ontario publica parking/rest live; inspeção CVSE usa sinal na estrada + crowd.
