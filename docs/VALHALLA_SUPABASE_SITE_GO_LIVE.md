# Valhalla + Supabase + Site Go-Live

## Current Routing Stack

- **Valhalla:** production truck routing, US + Canada, HTTPS at `https://valhalla.truckereasy.com`.
- **Free plan:** MapKit car route fallback.
- **Standard plan:** Valhalla truck route and avoid-tolls option.
- **Premium plan:** Route Easy / Fuel Smart, AI suggestions, DOT/HOS and logbook-aware guidance.

## Supabase Required Now

Apply these local migrations before TestFlight/public testing:

- `supabase/migrations/20260522100000_poi_places_fuel_prices.sql`
- `supabase/migrations/20260526182454_places_near_app_compatibility.sql`
- `supabase/migrations/20260526180000_fuel_intel_reports.sql`

Live project checked:

- Project: `usowafvqawbunyhmfscx`
- `places_near` RPC: compatible with the iOS app.
- `fuel_price_reports` and `fuel_receipts`: created.
- Storage bucket `fuel-receipts`: private.
- `poi_places`: currently needs real POI ingestion before Supabase can beat MapKit fallback.

## POI Data Source Decision

Do **not** add HERE just because Valhalla is done.

Valhalla solves routing geometry. POI richness should come first from:

- OSM/Overpass or osmium ingest into `poi_places`,
- driver reports and receipt/sign photos,
- partner feeds where legally allowed,
- EIA/NRCan regional diesel fallback.

Add HERE/TomTom/Amazon Location only later if OSM + driver reports are not good enough in a region. If used, make it a paid Premium enrichment layer, not the core route engine.

## Site Updates

The site should say:

- Free: car navigation with basic map.
- Standard: truck-safe routing for US/Canada, avoid tolls, DOT/HOS bar.
- Premium: smart route planning, fuel savings suggestions, food/medication reminders, scale monitoring, logbook-aware assistance.

Avoid promising live diesel prices everywhere until `poi_places` and `fuel_prices` are populated at scale.

## TestFlight Checklist

- `VALHALLA_SERVER_URLS = https:||valhalla.truckereasy.com`
- `SUPABASE_URL` and `SUPABASE_ANON_KEY` set in `TruckerEasy.secrets.xcconfig`.
- Run POI ingest for US/Canada regions.
- On iPhone with Wi-Fi off, calculate a route in Salt Lake City or another US city.
- Confirm Diagnostics shows Valhalla OK and Supabase OK.
- Confirm Free/Standard/Premium gates before public marketing.

## Next Technical Step

Migration is already applied on the live Supabase project. The next implementation block is the iOS UI for **Report Diesel**:

- manual diesel price report,
- photo/sign upload,
- fuel receipt upload,
- OCR extraction pipeline,
- insert into `fuel_price_reports` and `fuel_receipts`,
- later promotion of trusted reports into `fuel_prices`.
