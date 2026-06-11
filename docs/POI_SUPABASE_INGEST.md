# POI Supabase — Camada 2/3

## Architecture

- **Valhalla (EC2):** route geometry only
- **Supabase `poi_places`:** cold OSM list (Overpass weekly or osmium on EC2)
- **Supabase `fuel_prices`:** daily scraper (Camada 3)
- **App:** `places_near(lat, lon, radius_m)` — no Overpass at runtime

## Migration

`supabase/migrations/20260522100000_poi_places_fuel_prices.sql`

Compatibility with the live Supabase schema:

`supabase/migrations/20260526182454_places_near_app_compatibility.sql`

Fuel Intel receipt/report tables:

`supabase/migrations/20260526180000_fuel_intel_reports.sql`

## Ingest scripts

`backend/osm-poi-ingest/README.md`

## iOS (wired)

`TruckStopService.searchNearby` calls Supabase RPC `places_near` first; falls back to MapKit if empty or error.

`TruckStopService.lastDataSource` is `.supabase` or `.mapKit` after each search.

## Live status note

The live Supabase project has the `places_near` RPC and Fuel Intel tables applied, but `poi_places` must be populated before the app gets real Supabase truck stops. If `poi_places` is empty, the app safely falls back to MapKit.

**Recovery (May 2026):** OSM often tags Pilot/Love's as `amenity=fuel` only. Migration `20260527160000_poi_reclassify_truck_stops.sql` promotes branded HGV fuel → `truck_stop` (~1100 rows). Future ingests use improved `ingest_overpass.py` (ways + brand filter).

## Automatic POI updates

| Onde | Comando | Frequência |
|------|---------|------------|
| Mac (dev) | `./scripts/run_poi_ingest.sh` | Manual ou cron domingo |
| EC2 Valhalla | `backend/osm-poi-ingest/run_weekly.sh` | Cron `0 4 * * 0` |
| Dry-run | `./scripts/run_poi_ingest.sh --dry-run` | Teste uma região |

Requires `backend/osm-poi-ingest/.env` with `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY`.

Monitor: table `poi_ingest_runs` + `select poi_type, count(*) from poi_places group by 1`.

**APIs:** diesel prices = scraper/crowd (`fuel_prices`); showers/restaurants = OSM flags + driver reviews — **no** external restaurant API at runtime.

## iOS field mapping

Maps to `TruckStopItem` / `TruckStopAmenities`:

| DB column | App field |
|-----------|-----------|
| `name`, `brand`, `network` | name, network |
| `lat`, `lon` | coordinate |
| `has_shower` | amenities shower |
| `has_weigh_station` | CAT scale / weigh |
| `diesel_price_usd` (join) | amenities.dieselPrice |
