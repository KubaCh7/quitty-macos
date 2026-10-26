#!/bin/bash
# Installs the latest Quitty release into Applications and opens it:
#
#   curl -fsSL https://raw.githubusercontent.com/KubaCh7/quitty-macos/HEAD/scripts/install.sh | bash
#
# curl doesn't mark downloads as quarantined, so Gatekeeper doesn't block
# the app and there's no "Open Anyway" step.
set -euo pipefail

URL="https://github.com/KubaCh7/quitty-macos/releases/latest/download/Quitty.zip"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Downloading Quitty..."
curl -fsSL "$URL" -o "$WORK/Quitty.zip"
ditto -x -k "$WORK/Quitty.zip" "$WORK"

DEST="/Applications"
if [[ ! -w "$DEST" ]]; then
  DEST="$HOME/Applications"
  mkdir -p "$DEST"
fi

pkill -x Quitty 2>/dev/null || true
rm -rf "$DEST/Quitty.app"
ditto "$WORK/Quitty.app" "$DEST/Quitty.app"
xattr -cr "$DEST/Quitty.app"

echo "Installed Quitty in $DEST. Opening it..."
open "$DEST/Quitty.app"
