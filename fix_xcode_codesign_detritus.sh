#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
PROJECT_FILE="$PROJECT_DIR/trucker easy app.xcodeproj"
SCHEME="trucker easy app"
DERIVED_DATA="/tmp/trucker_easy_dd"

echo "Cleaning macOS metadata from project folders..."
xattr -d com.apple.FinderInfo "$PROJECT_DIR" 2>/dev/null || true
xattr -d com.apple.ResourceFork "$PROJECT_DIR" 2>/dev/null || true
xattr -d com.apple.FinderInfo "$PROJECT_DIR/trucker easy app" 2>/dev/null || true
xattr -d com.apple.ResourceFork "$PROJECT_DIR/trucker easy app" 2>/dev/null || true

echo "Building with DerivedData outside Desktop/iCloud..."
xcodebuild \
  -project "$PROJECT_FILE" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA" \
  build

echo "Done. If it succeeded, run the app from Xcode using the same DerivedData location."
