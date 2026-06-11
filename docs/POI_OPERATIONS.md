# POI Operations — Truck Stops & Weigh Stations (US/CA)

Operational guide for the data that powers **Truck Stops** and **Weigh Station** alerts in the iOS app.

## Architecture

| Layer | Role |
|-------|------|
| **Supabase `poi_places`** | OSM + gov ingest: truck_stop, fuel, weigh_station, rest_area |
| **`poi_operational_status`** | Live signals: weigh_status, site_open, parking, fuel |
| **`places_near` RPC** | App query: radius search + joins operational + diesel |
| **Road511** (`trucking-poi-feed`) | Optional partner feed for open/closed weigh + parking |
| **Gov ingest** (`government-poi-ingest/`) | Caltrans, ON511, BC CVSE, NTAD WIM, UDOT, etc. |
| **App** | `TruckStopService`, `WeighStationStatusService`, Horizon alerts |

## Cron on EC2 (recommended)

```bash
# Every 10 minutes — government + optional Road511
*/10 * * * * cd /opt/truckereasy && bash scripts/run_government_poi_sync.sh >> /var/log/gov-poi-sync.log 2>&1
```

`run_government_poi_sync.sh` runs:

1. `sync_government_poi.py` — static + dynamic gov sources
2. `sync_partner_feeds.py` — Road511 via Supabase Edge (if `ROAD511_API_KEY` set)

## Onde está cada API key

| API | Onde configurar | Status |
|-----|-----------------|--------|
| **Road511** (511/DOT agregado) | Supabase → Edge Functions → Secrets: `ROAD511_API_KEY` + **`ENABLE_ROAD511=true`** | ✅ Já configurado no projeto `usowafvqawbunyhmfscx` |
| **Ontario 511** | Nenhuma chave — URLs públicas em `sync_public_truck_feeds.py` | ✅ Grátis |
| **Caltrans / BC CVSE / NTAD** | Nenhuma chave — ingest gov Python | ✅ Grátis |
| **OHGO** (Ohio parking) | `backend/government-poi-ingest/.env` → `OHGO_API_KEY` | ⏳ Registo grátis: [publicapi.ohgo.com/accounts/registration](https://publicapi.ohgo.com/accounts/registration) |
| **TPIMS / I-10 TPAS** | `.env` → `TPIMS_DYNAMIC_URLS` (URLs por estado) | ⏳ Pedir URL ao DOT / [i10connects.com/resources](https://i10connects.com/resources) |
| **NextBillion** | Supabase secret `NEXTBILLION_API_KEY` | Opcional pago |
| **HERE** | `Config/TruckerEasy.secrets.xcconfig` → `HERE_API_KEY` | Opcional comercial |

**Não** colocar `ROAD511_API_KEY` no app iOS — só no Supabase Edge.

## Supabase Edge secrets

| Secret | Purpose |
|--------|---------|
| `ROAD511_API_KEY` | Live weigh + truck parking (Road511) |
| `ENABLE_ROAD511` | Deve ser `true` para activar Road511 nas functions |
| `NEXTBILLION_API_KEY` | Opcional — catálogo POI Browse |
| `SUPABASE_SERVICE_ROLE_KEY` | Upserts em `trucking-poi-feed` com `persist=1` |

## Weigh station open/closed logic (app)

1. **Official** — `weigh_status` from gov ingest (`open`, `closed`, `monitoring`)
2. When status is `monitoring`, app uses **`site_open`** signal (`gov_site_open` from `places_near`)
3. **Crowd** — `weigh_station_reports` (driver reports) as advisory only

View `poi_operational_latest` prefers actionable `open`/`closed` over `monitoring`.

## Truck stop dedup

- **DB**: migration `poi_truck_stop_dedup` removes duplicate rows (same type + lat/lon/name)
- **App**: `TruckStopService.dedupePlacesRows` collapses duplicates client-side before mapping pins

## Diesel & parking gaps

| Table | Current state | Action |
|-------|---------------|--------|
| `fuel_prices` | Sparse (~few rows) | Run fuel scraper / partner ingest on schedule |
| `truck_stop_parking_latest` | Often empty | Road511 sync + driver crowd reports |

## Health checks (app)

`IntegrationsHealthCheck` pings:

- Valhalla `/status`
- Supabase `places_near` (smoke query)
- Supabase `ops-feed` edge function

## Verify after deploy

```sql
-- Weigh stations with gov signal
select count(*) from poi_places p
join poi_operational_latest o on o.poi_place_id = p.id and o.signal_type = 'weigh_status'
where p.poi_type = 'weigh_station';

-- Actionable open/closed (not only monitoring)
select status_value, count(*) from poi_operational_latest
where signal_type in ('weigh_status','site_open')
group by 1;

-- Duplicate truck stops (should be 0 groups)
select count(*) from (
  select poi_type, round(lat::numeric,4), round(lon::numeric,4), lower(trim(name))
  from poi_places where poi_type = 'truck_stop'
  group by 1,2,3,4 having count(*) > 1
) t;
```

## iOS rebuild

After SQL + app changes, rebuild on device to pick up:

- `places_near` perf + dedup
- Weigh `gov_site_open` in alerts
- Throttled truck stop search (25 mi, 30 limit)
