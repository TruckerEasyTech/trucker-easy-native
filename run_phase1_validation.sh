#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
APP_DIR="$PROJECT_DIR/trucker easy app"
PROJECT_FILE="$PROJECT_DIR/trucker easy app.xcodeproj"
SCHEME="trucker easy app"
DERIVED_DATA="/tmp/trucker_easy_dd"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}✅ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
fail() { echo -e "${RED}❌ $1${NC}"; }

echo "=== PHASE 1 VALIDATION (Routing + Black Screen fix) ==="
echo ""

if [ ! -d "$PROJECT_DIR" ]; then
  fail "Project directory not found: $PROJECT_DIR"
  exit 1
fi

if [ ! -d "$APP_DIR" ]; then
  fail "App source directory not found: $APP_DIR"
  exit 1
fi

if [ ! -d "$PROJECT_FILE" ]; then
  fail "Xcode project not found: $PROJECT_FILE"
  exit 1
fi

pass "Project structure found"

echo ""
echo "Cleaning Finder metadata that can break codesign..."
xattr -d com.apple.FinderInfo "$PROJECT_DIR" 2>/dev/null || true
xattr -d com.apple.ResourceFork "$PROJECT_DIR" 2>/dev/null || true
xattr -d com.apple.FinderInfo "$APP_DIR" 2>/dev/null || true
xattr -d com.apple.ResourceFork "$APP_DIR" 2>/dev/null || true
pass "Metadata cleanup done"

echo ""
echo "Checking critical Phase 1 code markers..."

if grep -q "recordEvent(" "$APP_DIR/RoutingService.swift"; then
  pass "Routing telemetry is present"
else
  fail "Routing telemetry missing in RoutingService.swift"
  exit 1
fi

if grep -q "emergencyDirectRoute(" "$APP_DIR/ViewsHorizonView.swift"; then
  pass "Emergency fallback route is present"
else
  fail "Emergency fallback route missing in ViewsHorizonView.swift"
  exit 1
fi

if grep -q "map.overrideUserInterfaceStyle = .light" "$APP_DIR/ViewsHorizonMapSurface.swift"; then
  pass "Map forced to light style (black overlay mitigation)"
else
  warn "Light style enforcement not found in ViewsHorizonMapSurface.swift"
fi

if grep -q "setUserTrackingMode(.follow" "$APP_DIR/ViewsHorizonMapSurface.swift"; then
  pass "2D follow tracking mode configured"
else
  warn "Expected .follow tracking mode not found"
fi

echo ""
echo "Running build (DerivedData in /tmp)..."
xcodebuild \
  -project "$PROJECT_FILE" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA" \
  build

echo ""
pass "BUILD SUCCESSFUL"
echo ""
echo "Next quick smoke test in Xcode/device:"
echo "1) Open app and start a route with internet ON (expect provider success/fallback notice only if needed)"
echo "2) Toggle bad network and request route again (expect emergency fallback line, not route crash)"
echo "3) Enter navigation view and confirm map has no black overlay"
echo "4) Confirm route still navigates when provider degrades"
