#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILT_APP="$REPO_ROOT/.build/Quota Orbits.app"
INSTALL_DIR="/Users/example/Applications"
INSTALLED_APP="$INSTALL_DIR/Quota Orbits.app"

"$SCRIPT_DIR/build-app.sh"
mkdir -p "$INSTALL_DIR"

if [[ -e "$INSTALLED_APP" ]]; then
  BACKUP_APP="$INSTALLED_APP.backup-$(date +%Y%m%d-%H%M%S)"
  if [[ -e "$BACKUP_APP" ]]; then
    echo "Backup already exists: $BACKUP_APP" >&2
    exit 3
  fi
  mv "$INSTALLED_APP" "$BACKUP_APP"
  echo "Previous app moved to $BACKUP_APP"
fi

ditto "$BUILT_APP" "$INSTALLED_APP"
open "$INSTALLED_APP"
echo "$INSTALLED_APP"
