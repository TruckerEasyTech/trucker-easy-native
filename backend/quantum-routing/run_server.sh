#!/usr/bin/env bash
# Servidor FastAPI de otimização (TSP / ordem de paragens). Geometria de estrada continua no Valhalla (outro processo/porta).
#
# O `app/main.py` carrega automaticamente `.env` nesta pasta (python-dotenv).
#
# Uso (a partir desta pasta, com .venv ativo):
#   chmod +x run_server.sh
#   ./run_server.sh              → porta 8003 (Opção 3: Valhalla tipicamente na 8002)
#   PORT=8002 ./run_server.sh    → Opção 2: só este serviço na 8002 (Valhalla parado)
#
set -euo pipefail
cd "$(dirname "$0")"
PORT="${PORT:-8003}"
exec uvicorn app.main:app --host 0.0.0.0 --port "${PORT}"
