#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_BUNDLE="$REPO_ROOT/.build/Quota Orbits.app"

cd "$REPO_ROOT"
swift build -c release --product QuotaOrbits
BIN_DIR="$(swift build -c release --show-bin-path)"

case "$APP_BUNDLE" in
  "$REPO_ROOT"/.build/*) ;;
  *)
    echo "Refusing unsafe bundle path" >&2
    exit 2
    ;;
esac

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
ditto "$BIN_DIR/QuotaOrbits" "$APP_BUNDLE/Contents/MacOS/QuotaOrbits"
ditto "$REPO_ROOT/Packaging/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
codesign --force --deep --sign - "$APP_BUNDLE"

echo "$APP_BUNDLE"
