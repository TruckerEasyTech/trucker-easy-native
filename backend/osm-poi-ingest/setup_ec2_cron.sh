#!/usr/bin/env bash
# Instala cron automático na EC2 (user ubuntu).
# Uso: cd ~/osm-poi-ingest && bash setup_ec2_cron.sh
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="${HOME}/logs"
mkdir -p "${LOG_DIR}"

chmod +x "${DIR}/run_gov_sync.sh" 2>/dev/null || true
chmod +x "${DIR}/run_weekly_poi.sh" 2>/dev/null || true

MARKER="# trucker-easy-poi-cron"

if crontab -l 2>/dev/null | grep -q "${MARKER}"; then
  echo "Cron já instalado. Entradas actuais:"
  crontab -l | grep -A5 "${MARKER}" || true
  echo ""
  echo "Para reinstalar: crontab -e e apaga o bloco ${MARKER}"
  exit 0
fi

TMP="$(mktemp)"
crontab -l 2>/dev/null > "${TMP}" || true

cat >> "${TMP}" << EOF

${MARKER}
# Gov feeds (Ontario 511 + Caltrans + OHGO) — a cada 10 min
*/10 * * * * cd ${DIR} && . .venv/bin/activate && set -a && . ./.env && set +a && ./run_gov_sync.sh >> ${LOG_DIR}/truckereasy-gov-poi.log 2>&1
# OSM + NTAD — domingo 04:00 UTC
0 4 * * 0 cd ${DIR} && . .venv/bin/activate && set -a && . ./.env && set +a && ./run_weekly_poi.sh
EOF

crontab "${TMP}"
rm -f "${TMP}"

echo "✅ Cron instalado:"
crontab -l | tail -5
echo ""
echo "Logs:"
echo "  ${LOG_DIR}/truckereasy-gov-poi.log  (gov, cada 10 min)"
echo "  ${LOG_DIR}/poi-weekly-YYYYMMDD.log    (OSM+NTAD, domingo)"
