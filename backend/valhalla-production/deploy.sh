#!/usr/bin/env bash
# ============================================================
# Valhalla Production Deploy — Trucker Easy
#
# Deploys truck-aware routing on a DigitalOcean droplet with
# HTTPS via Caddy reverse proxy + Let's Encrypt auto-SSL.
#
# Requirements:
#   - DigitalOcean account (or any VPS with Docker)
#   - A domain name pointing to the server IP (e.g. valhalla.truckereasy.com)
#   - SSH access to the server
#
# Cost: ~$48/month (8GB RAM droplet) — routes unlimited drivers
#
# Usage:
#   1. Create a DigitalOcean droplet: Ubuntu 24.04, 8GB RAM, 160GB SSD
#   2. Point your domain A record to the droplet IP
#   3. SSH into the server and run this script:
#      curl -sSL https://raw.githubusercontent.com/.../deploy.sh | bash -s -- valhalla.truckereasy.com
#   4. After deploy, update TruckerEasy.secrets.xcconfig:
#      VALHALLA_SERVER_URL = https:||valhalla.truckereasy.com
# ============================================================

set -euo pipefail

DOMAIN="${1:?Usage: deploy.sh <your-domain.com>}"
DATA_DIR="/opt/valhalla"

echo "=== Trucker Easy — Valhalla Production Deploy ==="
echo "Domain: $DOMAIN"
echo "Data:   $DATA_DIR"
echo ""

# 1. Install Docker + Docker Compose
echo "[1/6] Installing Docker..."
if ! command -v docker &>/dev/null; then
  curl -fsSL https://get.docker.com | sh
  systemctl enable docker
  systemctl start docker
fi

# 2. Install Caddy (HTTPS reverse proxy with auto Let's Encrypt)
echo "[2/6] Installing Caddy..."
if ! command -v caddy &>/dev/null; then
  apt-get update -qq
  apt-get install -y -qq debian-keyring debian-archive-keyring apt-transport-https
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -qq
  apt-get install -y -qq caddy
fi

# 3. Download OSM — default US + Canada only (~14GB PBF, fits 96GB EBS better than full NA)
echo "[3/6] Downloading OSM data (US + Canada)..."
mkdir -p "$DATA_DIR/custom_files"
PBF_OUT="$DATA_DIR/custom_files/us-canada.osm.pbf"
if [ ! -f "$PBF_OUT" ]; then
  apt-get install -y -qq osmium-tool wget
  US_PBF="$DATA_DIR/us-latest.osm.pbf"
  CA_PBF="$DATA_DIR/canada-latest.osm.pbf"
  if [ ! -f "$US_PBF" ]; then
    wget -q --show-progress -O "$US_PBF" \
      "https://download.geofabrik.de/north-america/us-latest.osm.pbf"
  fi
  if [ ! -f "$CA_PBF" ]; then
    wget -q --show-progress -O "$CA_PBF" \
      "https://download.geofabrik.de/north-america/canada-latest.osm.pbf"
  fi
  osmium merge "$US_PBF" "$CA_PBF" -o "$PBF_OUT" --overwrite
  rm -f "$US_PBF" "$CA_PBF"
  # Remove legacy full-NA extract if present (frees ~12–18GB before tile build)
  rm -f "$DATA_DIR/north-america-latest.osm.pbf" \
    "$DATA_DIR/custom_files/north-america-latest.osm.pbf"
fi

# 4. Build Valhalla tiles
echo "[4/6] Building truck routing tiles (US+CA, ~3–6h; elevation off saves disk/RAM)..."
cat > "$DATA_DIR/docker-compose.yml" <<'COMPOSE'
version: "3.8"
services:
  valhalla:
    image: ghcr.io/gis-ops/docker-valhalla/valhalla:latest
    container_name: valhalla-truck
    restart: unless-stopped
    ports:
      - "8002:8002"
    volumes:
      - ./custom_files:/custom_files
    environment:
      - tile_urls=
      - use_tiles_ignore_pbf=False
      - build_elevation=False
      - build_admins=True
      - build_time_zones=True
      - serve_tiles=True
      - force_rebuild=False
COMPOSE

cd "$DATA_DIR"
docker compose up -d

echo "Waiting for Valhalla to build tiles and start (checking every 60s)..."
for i in $(seq 1 180); do
  if curl -sf http://localhost:8002/status > /dev/null 2>&1; then
    echo "Valhalla is ready!"
    break
  fi
  echo "  Still building tiles... ($((i * 60 / 60)) min elapsed)"
  sleep 60
done

# 5. Configure Caddy for HTTPS
echo "[5/6] Configuring HTTPS via Caddy..."
cat > /etc/caddy/Caddyfile <<CADDY
$DOMAIN {
    reverse_proxy localhost:8002
    encode gzip

    header {
        X-Content-Type-Options nosniff
        X-Frame-Options DENY
        Referrer-Policy strict-origin-when-cross-origin
    }
}
CADDY

systemctl restart caddy
sleep 5

# 6. Verify
echo "[6/6] Verifying deployment..."
echo ""

if curl -sf "https://$DOMAIN/status" > /dev/null 2>&1; then
  echo "============================================"
  echo "  ✅ Valhalla deployed successfully!"
  echo ""
  echo "  URL:  https://$DOMAIN"
  echo "  Test: curl https://$DOMAIN/status"
  echo ""
  echo "  Update your xcconfig:"
  echo "  VALHALLA_SERVER_URL = https:||$DOMAIN"
  echo "============================================"
else
  echo "⚠️  HTTPS not ready yet (SSL cert may take 1-2 min)."
  echo "  Check: curl -v https://$DOMAIN/status"
  echo "  Logs:  journalctl -u caddy -f"
  echo "  Valhalla: docker logs valhalla-truck --tail 50"
fi
