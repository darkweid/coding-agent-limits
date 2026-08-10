#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_BUNDLE="$REPO_ROOT/.build/Quota Orbits.app"
RESOURCE_BUNDLE_NAME="QuotaOrbits_QuotaOrbitsUI.bundle"

cd "$REPO_ROOT"
swift build -c release --product QuotaOrbits
BIN_DIR="$(swift build -c release --show-bin-path)"
RESOURCE_BUNDLE="$BIN_DIR/$RESOURCE_BUNDLE_NAME"

if [[ ! -d "$RESOURCE_BUNDLE" ]]; then
  echo "Required UI resource bundle is missing" >&2
  exit 2
fi

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
ditto "$RESOURCE_BUNDLE" "$APP_BUNDLE/Contents/Resources/$RESOURCE_BUNDLE_NAME"
codesign --force --deep --sign - "$APP_BUNDLE"

echo "$APP_BUNDLE"
