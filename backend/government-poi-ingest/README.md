# Government POI ingest (USDOT NTAD + state operational feeds)

Free public-domain truck parking / weigh **locations** from USDOT NTAD (Jason's Law / FHWA WIM).
Real-time weigh **open/closed** is not published nationally — combine crowd reports + state feeds (OHGO, TPIMS).

## Setup

```bash
cd backend/government-poi-ingest
cp .env.example .env
pip install -r requirements.txt
```

## NTAD locations (run weekly, after OSM ingest)

```bash
python ingest_ntad.py --dry-run
python ingest_ntad.py
```

## State operational feeds (run every 5–10 min via cron on EC2)

```bash
# Free public feeds — Ontario 511 + Caltrans (preferred)
python sync_public_truck_feeds.py

# US state feeds (OHGO, TPIMS) when configured
python sync_operational_feeds.py
```

See **`docs/POI_FREE_PUBLIC_FEEDS.md`** for the full $0 stack (OSM, NTAD, 511 provincial, crowd).

Road511 / NextBillion are **disabled by default** (paid, 15 min delay on trial). Do not use unless `ENABLE_ROAD511=true` on Edge Functions.
