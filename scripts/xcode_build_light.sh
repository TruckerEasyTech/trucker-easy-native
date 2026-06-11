#!/bin/zsh
# Build iOS leve: DerivedData fora do Desktop/iCloud, 1 job de compilação (8GB RAM).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DD="${XCODE_DERIVED_DATA:-$HOME/Developer/DerivedData/trucker-easy-app}"
mkdir -p "$DD"

echo "Build leve → DerivedData: $DD"
echo "(Feche simuladores extras e Chrome antes, se o Mac travar.)"
echo ""

xcodebuild \
  -workspace "$ROOT/trucker easy app.xcworkspace" \
  -scheme "trucker easy app" \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DD" \
  -parallelizeTargets=NO \
  -jobs 1 \
  build

echo ""
echo "OK. Abra o Xcode e aponte Derived Data para: $DD"
