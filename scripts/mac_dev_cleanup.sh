#!/bin/zsh
# Libera disco/RAM para Xcode no Mac (8–16 GB RAM). Seguro de rodar a qualquer momento.
# Uso: ./scripts/mac_dev_cleanup.sh           — limpeza padrão (~2–3 GB)
#      ./scripts/mac_dev_cleanup.sh --deep    — inclui simuladores antigos e archives
set -euo pipefail
setopt null_glob 2>/dev/null || true

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEEP=false
[[ "${1:-}" == "--deep" ]] && DEEP=true

echo "=== Trucker Easy — limpeza dev (Mac) ==="
echo "Projeto: $ROOT"
df -h / | awk 'NR==1 || NR==2 {print}'
echo ""

freed=0

delete_dir() {
  local dir="$1"
  if [[ -d "$dir" ]]; then
    local size
    size=$(du -sk "$dir" 2>/dev/null | awk '{print $1}')
    echo "  Removendo $(du -sh "$dir" 2>/dev/null | awk '{print $1}') → $dir"
    rm -rf "$dir"
    freed=$((freed + size))
  fi
}

delete_file() {
  local f="$1"
  if [[ -f "$f" ]]; then
    local size
    size=$(du -sk "$f" 2>/dev/null | awk '{print $1}')
    echo "  Removendo $(du -sh "$f" 2>/dev/null | awk '{print $1}') → $f"
    rm -f "$f"
    freed=$((freed + size))
  fi
}

echo "[1/6] DerivedData dentro do projeto (Desktop/iCloud — NÃO deve ficar aqui)"
for d in "$ROOT"/.derivedData*; do
  [[ -e "$d" ]] || continue
  delete_dir "$d"
done
delete_file "$ROOT/build-output.log"

echo ""
echo "[2/6] DerivedData Xcode (mantém só o build mais recente deste app)"
DD="$HOME/Library/Developer/Xcode/DerivedData"
if [[ -d "$DD" ]]; then
  ls -dt "$DD"/trucker_easy_app-* 2>/dev/null | tail -n +2 | while read -r old; do
    delete_dir "$old"
  done
  # Outros projetos antigos (>14 dias) — libera muito disco
  find "$DD" -maxdepth 1 -type d -mtime +14 2>/dev/null | while read -r old; do
    [[ "$old" == "$DD" ]] && continue
    delete_dir "$old"
  done
fi

echo ""
echo "[3/6] Caches SwiftPM + Module cache (regeneram no próximo build)"
delete_dir "$HOME/Library/Caches/org.swift.swiftpm"
delete_dir "$HOME/Library/Developer/Xcode/DerivedData/ModuleCache.noindex"

echo ""
echo "[4/6] CocoaPods download cache (opcional — pod install refaz)"
delete_dir "$HOME/Library/Caches/CocoaPods"

if $DEEP; then
  echo ""
  echo "[5/6] DEEP — Simuladores inactivos + device logs"
  xcrun simctl delete unavailable 2>/dev/null || true
  delete_dir "$HOME/Library/Developer/CoreSimulator/Caches"
  find "$HOME/Library/Logs/CoreSimulator" -type f -mtime +7 -delete 2>/dev/null || true

  echo ""
  echo "[6/6] DEEP — Xcode Archives antigos (>30 dias)"
  ARCH="$HOME/Library/Developer/Xcode/Archives"
  if [[ -d "$ARCH" ]]; then
    find "$ARCH" -type d -name "*.xcarchive" -mtime +30 2>/dev/null | while read -r arc; do
      delete_dir "$arc"
    done
  fi
else
  echo ""
  echo "[5–6] Pulado (use --deep para simuladores e archives)"
fi

echo ""
echo "=== Concluído ==="
echo "Espaço liberado: ~$((freed / 1024)) MB"
df -h / | awk 'NR==2 {print "Disco livre agora:", $4, "("$5" usado)"}'
echo ""
echo "Recomendações permanentes (iMac com pouco espaço):"
echo "  1. Mover repo para ~/Developer/trucker-easy-app (fora do Desktop/iCloud)"
echo "  2. Xcode → Settings → Locations → Derived Data → ~/Developer/DerivedData"
echo "  3. Valhalla Docker: tiles Europa ~20+ GB — volume Docker separado ou EC2"
echo "  4. ./scripts/xcode_build_light.sh em vez de build completo no Xcode"
echo "  5. Rodar este script semanalmente: ./scripts/mac_dev_cleanup.sh --deep"
