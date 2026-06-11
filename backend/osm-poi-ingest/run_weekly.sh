#!/usr/bin/env bash
# EC2: ingest semanal + log em poi_ingest_runs (opcional via curl).
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

if [[ -f .env ]]; then set -a; source .env; set +a; fi

python3 -m pip install -q -r requirements.txt
python3 ingest_overpass.py --all
echo "Weekly POI ingest done $(date -Iseconds)"
