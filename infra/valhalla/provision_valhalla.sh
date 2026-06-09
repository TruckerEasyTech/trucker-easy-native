#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$ROOT_DIR/data"
PBF_URL="${PBF_URL:-https://download.geofabrik.de/north-america/us-latest.osm.pbf}"
PBF_FILE="$DATA_DIR/$(basename "$PBF_URL")"
PORT="${VALHALLA_PORT:-8002}"

usage() {
  cat <<'USAGE'
Usage: ./provision_valhalla.sh [--check]

  --check   Verify host prerequisites without downloading map data or starting containers.

Environment:
  PBF_URL                  OSM extract URL. Defaults to US Geofabrik extract.
  VALHALLA_PORT            Host port. Defaults to 8002.
  VALHALLA_SERVER_THREADS  Container worker threads.
  VALHALLA_FORCE_REBUILD   True/False tile rebuild flag.
USAGE
}

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name" >&2
    return 1
  fi
}

check_prerequisites() {
  local missing=0
  require_command curl || missing=1
  require_command docker || missing=1

  if command -v docker >/dev/null 2>&1; then
    if ! docker compose version >/dev/null 2>&1; then
      echo "Docker is installed, but 'docker compose' is unavailable." >&2
      missing=1
    fi
    if ! docker info >/dev/null 2>&1; then
      echo "Docker is installed, but the daemon/socket is not reachable." >&2
      missing=1
    fi
  fi

  return "$missing"
}

if [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

if [ "${1:-}" = "--check" ]; then
  check_prerequisites
  echo "Valhalla host prerequisites are available."
  exit 0
fi

check_prerequisites

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
