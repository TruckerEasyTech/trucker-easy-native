# OSM POI ingest → Supabase (Camada 2)

Populates `poi_places` from OpenStreetMap (free). The iOS app will call `places_near` instead of MapKit for truck stops.

## EC2 — uma pasta só (`~/osm-poi-ingest`)

| Comando | O que faz |
|---------|-----------|
| `python3 ingest_osmium.py …` | Truck stops / fuel OSM → Supabase |
| **`./run_gov_sync.sh`** | **Balanças + status oficial** (Ontario 511, Caltrans) |
| `python3 sync_public_truck_feeds.py` na raiz | ❌ Errado — use **`./run_gov_sync.sh`** (scripts em `gov/`) |

```bash
cd ~/osm-poi-ingest
source .venv/bin/activate
cp .env.example .env
./run_gov_sync.sh
```

Se faltar a pasta `gov/`, copia de novo `backend/osm-poi-ingest/` do Mac para a EC2.

### Cron automático (recomendado)

Uma vez na EC2:

```bash
cd ~/osm-poi-ingest
bash setup_ec2_cron.sh
```

| Job | Quando | Script |
|-----|--------|--------|
| Gov (511, Caltrans, OHGO) | cada **10 min** | `run_gov_sync.sh` |
| OSM + NTAD | **domingo 04:00 UTC** | `run_weekly_poi.sh` |

Logs: `~/logs/truckereasy-gov-poi.log` e `~/logs/poi-weekly-YYYYMMDD.log`

Verificar: `crontab -l`


```bash
cd "/Users/thaiskeller/Desktop/trucker easy app"
supabase db push
# or paste these in SQL Editor:
# - supabase/migrations/20260522100000_poi_places_fuel_prices.sql
# - supabase/migrations/20260526182454_places_near_app_compatibility.sql
```

## 2. Configure env

```bash
cd backend/osm-poi-ingest
cp .env.example .env
# Edit: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (never commit .env)
```

## 3. Test Overpass (one region, no upload)

```bash
pip install -r requirements.txt
export $(grep -v '^#' .env | xargs)
python ingest_overpass.py --region us-tx-dfw --dry-run
```

Visual check: [Overpass Turbo](https://overpass-turbo.eu/) with the query from `ingest_overpass.py`.

## 4. Ingest to Supabase

```bash
python ingest_overpass.py --region us-tx-dfw
python ingest_overpass.py --all   # 19 tiles US+CA sample; extend regions_us_ca.json for all states
```

Fair-use: default **25s pause** between regions. Run **weekly**, not per app session.

Live note: if `poi_places` has 0 rows, the iOS app will still work, but it is using MapKit fallback for nearby truck stops instead of Supabase POIs.

Use smaller metro/highway corridor tiles first (`us-tx-dfw`, `us-tx-houston`, `us-ut-slc`). Full-state boxes can be rejected or timed out by public Overpass servers.

## TestFlight corridor: Minnesota → New Jersey

For a driver testing from Minnesota toward New Jersey, load these smaller corridor tiles gradually:

```bash
python ingest_overpass.py --region us-mn-twin-cities --dry-run
python ingest_overpass.py --region us-il-chicago --dry-run
python ingest_overpass.py --region us-in-toll-road --dry-run
python ingest_overpass.py --region us-oh-turnpike --dry-run
python ingest_overpass.py --region us-pa-west --dry-run
python ingest_overpass.py --region us-pa-i80-east --dry-run
python ingest_overpass.py --region us-nj-north --dry-run
```

Observed dry-run counts:

| Region | POIs |
|--------|------|
| `us-mn-twin-cities` | 12 |
| `us-il-chicago` | 49 |
| `us-in-toll-road` | 38 |
| `us-oh-turnpike` | 69 |
| `us-pa-west` | 13 |
| `us-pa-i80-east` | 23 |
| `us-nj-north` | 19 |

`us-wi-madison` and `us-wi-milwaukee` timed out on public Overpass and should be split into smaller highway/city tiles before upload.

## 5. Verify in Supabase

```sql
select poi_type, count(*) from poi_places group by 1 order by 2 desc;

select * from places_near(30.2672, -97.7431, 50000, array['fuel','truck_stop'], 20);
-- Austin, TX example
```

## 6. App (next step)

Replace `TruckStopService` MapKit search with:

```swift
// RPC: places_near(lat, lon, radius_m, poi_types, limit)
```

`fuel_prices` table is ready for Camada 3 (daily scraper); join via `fuel_prices_latest` in `places_near`.

## Recommended scale path: osmium on EC2

Use this when Valhalla is already built on EC2. It reads the same US+Canada PBF, avoids Overpass rate limits, and uploads directly to Supabase.

### 1. Copy the ingest folder to EC2

From your Mac:

```bash
cd "/Users/thaiskeller/Desktop/trucker easy app"
scp -i ~/.ssh/truckereasy-valhalla.pem -r backend/osm-poi-ingest ubuntu@VALHALLA_EC2_IP:/home/ubuntu/osm-poi-ingest
```

### 2. Install dependencies on EC2

On EC2:

```bash
cd /home/ubuntu/osm-poi-ingest
sudo apt-get update
sudo apt-get install -y osmium-tool python3-venv
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
```

### 3. Configure Supabase on EC2

Do not commit this key. Export it only in the EC2 shell session:

```bash
export SUPABASE_URL="https://usowafvqawbunyhmfscx.supabase.co"
export SUPABASE_SERVICE_ROLE_KEY="PASTE_SERVICE_ROLE_KEY"
```

### 4. Dry-run from Valhalla PBF

```bash
python3 ingest_osmium.py --dry-run
```

Expected source file:

```bash
ls -lh /opt/valhalla/custom_files/us-canada.osm.pbf
```

### 5. Upload to Supabase

Only run after dry-run shows reasonable POI rows:

```bash
python3 ingest_osmium.py /opt/valhalla/custom_files/us-canada.osm.pbf
```

Zero extra Geofabrik download — uses the PBF you already built tiles from.

### 6. Verify

```sql
select poi_type, count(*) from poi_places group by 1 order by 2 desc;
select * from places_near(44.9778, -93.2650, 80467, array['fuel','truck_stop','services','shower'], 20);
```

## Tables

| Table | Purpose |
|-------|---------|
| `poi_places` | Static OSM POIs |
| `fuel_prices` | Daily diesel per place |
| `fuel_prices_latest` | View for app |
| `places_near()` | RPC for driver map |
