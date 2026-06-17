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

## Traffic cameras (state 511 feeds → `traffic_cameras`)

Câmeras de trânsito dos DOTs estaduais (dado público, grátis; cada estado dá uma chave de dev grátis).
A localização vai pro Supabase; a **imagem é uma URL ao vivo do DOT** (refresca ao abrir).

```bash
# roda no cron, ex.: a cada 30-60 min (câmeras mudam de local raramente)
python sync_traffic_cameras.py            # só busca os estados com chave configurada
python sync_traffic_cameras.py --dry-run  # mostra o que pegaria, sem gravar
```

**Chaves grátis por estado (registrar no portal 511 de cada um) → env vars:**
`NY511_KEY` (511ny.org), `GA511_KEY` (511ga.org), `WI511_KEY` (511wi.gov), `FL511_KEY` (fl511.com),
`AZ511_KEY` (az511.com), `NV511_KEY` (nvroads.com). Estado **sem chave = pulado** (nada fabricado).
Adicionar mais estados = uma linha em `CAMERA_FEEDS` + a env da chave.

Requer a migração `supabase/migrations/20260617120000_traffic_cameras.sql` aplicada (tabela +
RLS de leitura pública + RPC `traffic_cameras_near` que o app usa pra pegar só as do corredor).
