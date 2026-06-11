# CLAUDE.md — Trucker Easy

> Project context for Claude / Fable 5. Auto-generated 2026-06-11 from a read-only
> terminal exploration (no editor opened). Treat as a map, not gospel — verify
> specifics against the code before relying on them.

## What this is

**Trucker Easy** is a **native iOS app (Swift, iOS 18.0+)** for professional truck
drivers and small fleets in the **US & Canada**, plus a backend monorepo in the same
folder. It does truck-aware routing/navigation, DOT Hours-of-Service tracking, fleet
dispatch, fuel/expense/IFTA tracking, driver wellness, and crowd-sourced road
intelligence (weigh stations, parking, truck stops, fuel prices).

- **Active working copy:** `~/Desktop/trucker easy app/` (this folder). An older second
  copy exists on the X9 Pro external SSD — confirm which is source of truth before editing.
- This is **NOT** the Flutter project at `~/Trucker-Easy` (a different/old prototype).

## Tech stack

| Layer | Tech |
|---|---|
| Language / UI | Swift, **SwiftUI** (UIKit only for system bridges) |
| Concurrency | **async/await** + `@Observable` / `@MainActor` (avoid Combine) |
| Persistence | **SwiftData** (`@Model`), fallback to in-memory on migration failure |
| Maps | **Mapbox** SPM (mapbox-maps-ios v11.23) + turf-swift; **MapKit** as fallback |
| Navigation SDK | **NextBillion** (local binary, `LocalPackages/NextBillionNavigationBinary`) |
| Routing engine | **Valhalla** (self-hosted, truck costing) on AWS |
| Backend / Auth / DB | **Supabase** (REST + Auth + Edge Functions + Postgres) |
| Dependencies | SPM for Mapbox; **Podfile is effectively empty** (no real CocoaPods) |

Config/secrets live in `Config/TruckerEasy.secrets.xcconfig` (xcconfig keys like
`ValhallaServerURL(s)`, `SupabaseURL`, `SupabaseAnonKey`, `RouteOptimizationAPIKey`,
Mapbox key). **Never hardcode secrets in Swift; never commit the xcconfig.**

## Architecture (iOS app)

Flat, service-oriented (not MVVM/TCA). Singleton services + `@Observable` state.
Source lives in `trucker easy app/trucker easy app/`, with filenames flattened by
prefix (e.g. `ViewsHorizonView.swift`, `ServicesSupabaseClient.swift`):

- **Views/** — SwiftUI screens (Horizon map, Check-up/wellness, Cabin/docs, RoadTalk/community, Profile)
- **Services/** — singletons: routing, Supabase, dispatch, fuel pricing, quantum optimization, wellness sync
- **Models/** — SwiftData `@Model` + Codable (Trip, FuelPurchase, Expense, IFTAReport, TruckProfile, RouteOptimization, GeofenceRegion)
- **Utilities/** — DOT HOS engine, regional settings, navigation, voice
- **Horizon\*** — map navigation subsystem (overlays, sheets, chrome)

### Key files
- `trucker_easy_appApp.swift` — `@main`, SwiftData init, push/AppDelegate
- `AppEntryView.swift` → `ViewsMainTabView.swift` — splash → onboarding → 5-tab UI
- `ViewsHorizonView.swift` (~3.4k lines) — main map + navigation
- `RoutingService.swift` — routing chain: **Valhalla → OSRM → MapKit** fallback
- `ServicesValhallaRoutingService.swift` — Valhalla `POST /route` client (truck costing)
- `ServicesQuantumRouteOptimizationClient.swift` — `POST /v1/optimize` (multi-stop reorder)
- `ServicesSupabaseClient.swift` (~870 lines) — REST client (auth, reports, push tokens)
- `ServicesDispatchService.swift` — load assignments / deep links
- `UtilitiesDotHOS.swift` — HOS compliance (11h drive / 14h window)
- `LocationManager.swift` — Core Location wrapper

## How it talks to the backend

**Valhalla (routing)** — runs on **AWS EC2 in the Oregon region (us-west-2)**, NOT in
local Docker. Domain `valhalla.truckereasy.com` (IP 44.246.100.46). Map data = **US + Canada
OSM** tiles (~14GB PBF, built on EC2). App sends origin/dest + truck dims (height/weight/
length/axle) with `"costing":"truck"`. Deploy tooling in `backend/valhalla-production/`
(`aws-oregon-valhalla-bootstrap.sh`, `deploy.sh`, `aws-oregon-teardown.sh`).
> Note: "Oregon" = the AWS datacenter region. The routed map area is all of US+Canada.

**Quantum-routing** — Python FastAPI middleware (EC2, host port `:8003`) that **reorders
multi-stop waypoints** (TSP) before Valhalla draws roads. Solvers: greedy default, optional
D-Wave / Amazon Braket. Source: `backend/quantum-routing/`.

**Supabase** (project ref `usowafvqawbunyhmfscx`) — email/password auth (JWT in
UserDefaults), plus Postgres tables for: `dispatched_loads`, `route_optimizations`,
`road_reports`, `weigh_station_reports`, `truck_stop_parking_reports`,
`truck_stop_reviews`, `shipper_facility_reviews`, `fuel_reports`/`fuel_price_reports`,
`community_posts`/`post_comments`, `driver_wellness_checkins`, `device_tokens`, `drivers`,
`poi_places`. Edge Functions in `supabase/functions/`: `health-check`, `ops-feed`,
`route-proxy`, `trucking-poi-feed`. Migrations in `supabase/migrations/`.

**POI ingest (backend, cron on EC2, $0 cost):**
- `backend/osm-poi-ingest/` — OSM truck stops/fuel → `poi_places` (app uses `places_near()` RPC)
- `backend/government-poi-ingest/` — USDOT NTAD + state feeds (Caltrans, ON511, OHGO, TPIMS) → weigh/parking status

**Other:** `ops-dashboard/` (React/Vite admin panel reading Supabase metrics);
`website-public/` (static, `.well-known/` only); `quantum-routing-service/`.

## Current state (from `docs/*.md`, mostly Portuguese)

**Working / shipped:**
- Core truck routing (3 modes: Fast / No-tolls / AI Smart) with Valhalla→OSRM→MapKit fallback
- Truck profile editor; dispatch login + pending-load banner; POI map pins + weigh-station alerts
- HOS timer (local only); health-check diagnostics; Lotus.ai wellness link (safe, link-only)
- Supabase migrations created; Valhalla EC2 HTTPS-ready; route-proxy Edge Function deployed

**Pending / blockers (TestFlight path, see `AMANHA_CHECKLIST.md`, `AWS_TU_FAZES.md`):**
1. Deploy **quantum-routing to EC2 `:8003`** (currently 502; "AI Smart" full optimization blocked). Sub-blocker: **SSH port 22 closed** on EC2 → use S3/git/temp SG to copy.
2. Confirm **Valhalla HTTPS domain → DNS A record**, set `VALHALLA_SERVER_URL` in xcconfig.
3. **AWS Free Tier** may block paid instance types (c5.xlarge) → verify billing or use DigitalOcean.
4. **POI/fuel data sparse** — static OSM/gov mostly loaded; diesel prices & parking predictions await driver-report MVP + aggregation.

**Not for MVP:** offline maps, real ELD integration, Lotus.ai live API (contract pending),
fuel-price OCR, GPS UI polish (Figma → SwiftUI, no logic change).

## Conventions (from code + `.cursor` history)

- 4-space indent; PascalCase types, camelCase members; `@State private var`, `let` for constants.
- Prefer async/await over Combine. Avoid force-unwrap. Search Apple docs for new APIs
  (Liquid Glass, FoundationModels, latest SwiftUI) rather than assuming.
- Keep changes scoped to the request; don't refactor unrelated code.

## Environment notes

- 8GB iMac M1 — memory-constrained. Xcode + Cursor + Docker run together (see global memory).
  Optimize around them; don't suggest closing them.
- The project sometimes lives on an **exFAT** external SSD (no symlinks/permissions) →
  occasional CodeSign/build quirks (`fix_xcode_codesign_detritus.sh` in root).
- Local Docker runs **Supabase** (not Valhalla). Valhalla is on AWS.

## Useful docs (`docs/`)
`AMANHA_CHECKLIST.md` (next steps), `AWS_TU_FAZES.md` (AWS tasks), `APP_STORE_ROTAS.md`
(submission strategy), `DEPLOY_VALHALLA_DO_MAC.md`, `FUEL_INTEL_ROUTE_PLANS.md`,
`GPS_UI_REFINEMENT_PLAN.md`, `LOTUS_*` (wellness partner), `LOVABLE_*` (dispatch portal).
