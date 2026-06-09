# Trucker Easy Production Navigation + Live Operations

This repository now contains the app-side integration plus deployable backend pieces for:

- production Valhalla truck routing;
- live operational `ops-feed` for parking and weigh-station status;
- national FHWA/NTAD WIM weigh-station baseline coverage;
- Xcode/iPhone smoke testing.

## 1. Production Valhalla

The iOS app reads `ValhallaServerURL` from the active Info.plist/xcconfig and calls:

```text
POST <ValhallaServerURL>/route
```

The request uses Valhalla truck costing with:

- height, width, length;
- gross weight and axle load in metric tonnes;
- axle count;
- HGV no-access penalty;
- truck-route preference.

### Deploy a dedicated Valhalla host

On a Linux host with Docker:

```bash
cd infra/valhalla
cp .env.example .env
./provision_valhalla.sh
```

Recommended production setup:

1. Put the host behind HTTPS (ALB, Nginx, Caddy, or Cloudflare Tunnel).
2. Use a stable domain, for example:
   `https://routing.truckereasy.com`
3. Set this in `Config/TruckerEasy.secrets.xcconfig`:

```xcconfig
ValhallaServerURL = https:||routing.truckereasy.com
```

`https:||...` is intentional for xcconfig files; Xcode treats `//` as a comment.

The app treats an empty or unresolved `$(ValhallaServerURL)` as not configured. Do not use the public demo server for production drivers.

## 2. Supabase `ops-feed`

The app already calls:

```text
GET https://<project-ref>.supabase.co/functions/v1/ops-feed?lat=<lat>&lon=<lon>&radius_km=80
```

This repository now includes:

```text
supabase/functions/ops-feed/index.ts
supabase/config.toml
```

The function aggregates:

- configured partner feeds from `OPERATIONAL_FEED_PROVIDER_URLS`;
- recent Supabase `road_reports`;
- recent Supabase `weigh_station_reports`;
- FHWA/NTAD WIM stations as monitoring-only baseline coverage.

### Deploy

Authenticate and link the Supabase project, then deploy:

```bash
supabase login
supabase link --project-ref qhwuwiiwdzqkjzjqgpvx
supabase functions deploy ops-feed
```

For headless/CI environments, configure:

- `SUPABASE_ACCESS_TOKEN`
- `SUPABASE_PROJECT_REF`

Then use `.github/workflows/deploy-supabase-functions.yml` or the MCP template in `.mcp.example.json`.
See `docs/SUPABASE_HEADLESS_MCP.md`.

Optional partner feed secrets:

```bash
supabase secrets set \
  OPERATIONAL_FEED_PROVIDER_URLS="https://partner-1.example.com,https://partner-2.example.com" \
  OPERATIONAL_FEED_API_KEY="<partner-api-key>"
```

Verify:

```bash
curl "https://qhwuwiiwdzqkjzjqgpvx.supabase.co/functions/v1/ops-feed?lat=32.7767&lon=-96.7970&radius_km=80" \
  -H "apikey: <Supabase anon/publishable key>"
```

Expected shape:

```json
{
  "parking_signals": [],
  "weigh_signals": [
    {
      "station_name": "DOT WIM Station WT4142 · TX",
      "latitude": 31.027637,
      "longitude": -93.978351,
      "status": "monitoring",
      "updated_at": null
    }
  ]
}
```

`monitoring` is not live open/closed. Real open/closed comes from partner feeds and driver reports.

## 3. iPhone/Xcode smoke test

Run on a real iPhone:

1. Open `trucker easy app.xcworkspace`.
2. Confirm `Config/TruckerEasy.secrets.xcconfig` has:
   - `SupabaseAnonKey`;
   - `MBXAccessToken` if using Mapbox rendering;
   - `ValhallaServerURL` pointing to production Valhalla.
3. Product > Clean Build Folder.
4. Select a physical iPhone.
5. Run.
6. Accept location permission.
7. Open Horizon.

Expected:

- GPS pill moves from `GPS weak` to `GPS live`.
- If GPS stalls, watchdog restarts location updates.
- Routing diagnostics shows `Valhalla: ok` for production, or `Valhalla: demo` if still on public demo.
- Stops > Weigh Stations shows Apple POI results plus FHWA/NTAD WIM stations.
- Weigh station banner shows open/closed when partner/crowd data exists, otherwise unknown/monitoring.

## 4. What still requires external operations

- Running `infra/valhalla/provision_valhalla.sh` on the Docker-capable Valhalla host.
- Deploying the Supabase Edge Function to the live Supabase project via Dashboard, local Supabase CLI, or GitHub Actions.
- Adding partner/state feed URLs and credentials.
- Running the iPhone smoke test on real hardware.
