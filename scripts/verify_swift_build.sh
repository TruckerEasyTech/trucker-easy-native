#!/bin/bash
#
# verify_swift_build.sh
#
# Compiles the Trucker Easy iOS app for the simulator WITHOUT code signing,
# and prints only the compile errors plus the final BUILD SUCCEEDED/FAILED line.
#
# Usage: ./scripts/verify_swift_build.sh
#
set -uo pipefail

ROOT="/Users/thaiskeller/Desktop/trucker easy app"
WORKSPACE="trucker easy app.xcworkspace"
SCHEME="trucker easy app"

cd "$ROOT" || { echo "ERROR: could not cd into project root"; exit 1; }

echo "Building scheme '$SCHEME' for iOS Simulator (no code signing)..."
echo "This can take several minutes on first build."
echo "----------------------------------------------------------------"

# Run the build, capture full log to a temp file, stream filtered output.
LOG="$(mktemp -t trucker_easy_build)"

xcodebuild \
    -workspace "$WORKSPACE" \
    -scheme "$SCHEME" \
    -sdk iphonesimulator \
    -destination "generic/platform=iOS Simulator" \
    CODE_SIGNING_ALLOWED=NO \
    build 2>&1 | tee "$LOG" \
    | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"

# Determine the real result from the captured log (grep above may exit non-zero).
if grep -q "BUILD SUCCEEDED" "$LOG"; then
    echo "----------------------------------------------------------------"
    echo "RESULT: BUILD SUCCEEDED"
    rm -f "$LOG"
    exit 0
else
    echo "----------------------------------------------------------------"
    echo "RESULT: BUILD FAILED"
    echo "Errors (if any) shown above. Full log kept at: $LOG"
    exit 1
fi
