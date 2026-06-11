#!/usr/bin/env bash
# Run from repo root before Product → Archive (Release).
# Fails fast if secrets or Mapbox token are missing for a real device build.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SECRETS="$ROOT/Config/TruckerEasy.secrets.xcconfig"

if [[ ! -f "$SECRETS" ]]; then
  echo "error: Missing $SECRETS — copy Config/TruckerEasy.secrets.example.xcconfig and fill values." >&2
  exit 1
fi

strip_val() {
  local line="$1"
  line="${line#*=}"
  echo "${line//[[:space:]]/}"
}

while IFS= read -r line || [[ -n "$line" ]]; do
  [[ "$line" =~ ^[[:space:]]*// ]] && continue
  [[ "$line" =~ ^[[:space:]]*MBXAccessToken[[:space:]]*= ]] || continue
  val="$(strip_val "$line")"
  if [[ -z "$val" ]]; then
    echo "error: MBXAccessToken is empty in TruckerEasy.secrets.xcconfig — Mapbox will not load." >&2
    exit 1
  fi
  if [[ "$val" == *'$('* ]]; then
    echo "error: MBXAccessToken still contains unexpanded \$(...) — check xcconfig inclusion on the target." >&2
    exit 1
  fi
  echo "ok: MBXAccessToken present (length ${#val})."
  exit 0
done <"$SECRETS"

echo "error: MBXAccessToken key not found in $SECRETS" >&2
exit 1
