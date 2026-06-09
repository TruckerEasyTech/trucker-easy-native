#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$ROOT_DIR/data"
PBF_URL="${PBF_URL:-https://download.geofabrik.de/north-america/us-latest.osm.pbf}"
PBF_FILE="$DATA_DIR/$(basename "$PBF_URL")"
PORT="${VALHALLA_PORT:-8002}"

mkdir -p "$DATA_DIR"

if [ ! -f "$PBF_FILE" ]; then
  echo "Downloading OSM extract: $PBF_URL"
  curl -L --fail --retry 3 --output "$PBF_FILE" "$PBF_URL"
else
  echo "OSM extract already exists: $PBF_FILE"
fi

echo "Starting Valhalla on port $PORT"
cd "$ROOT_DIR"
docker compose up -d

echo "Waiting for Valhalla health..."
for attempt in $(seq 1 60); do
  if curl -fsS "http://127.0.0.1:$PORT/status" >/dev/null 2>&1; then
    echo "Valhalla is responding at http://127.0.0.1:$PORT"
    exit 0
  fi
  sleep 5
done

echo "Valhalla did not become healthy in time. Check: docker compose logs -f" >&2
exit 1
