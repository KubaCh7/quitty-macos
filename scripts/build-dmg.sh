#!/usr/bin/env bash
# Builds build/Quitty.dmg from build/Quitty.app: a window showing the app, an
# arrow and an Applications shortcut to drag it onto. Run build-app.sh first.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Quitty.app"
if [[ ! -d "$APP" ]]; then
  echo "Missing $APP. Run scripts/build-app.sh first." >&2
  exit 1
fi

# dmgbuild writes the Finder window layout directly, so it works without a
# logged-in Finder (CI runners).
VENV="build/dmg-venv"
if [[ ! -x "$VENV/bin/dmgbuild" ]]; then
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --quiet "dmgbuild>=1.6"
fi

# One TIFF holding both resolutions, so the background is sharp on Retina.
tiffutil -cathidpicheck Resources/dmg-background.png Resources/dmg-background@2x.png \
  -out build/dmg-background.tiff

rm -f build/Quitty.dmg
"$VENV/bin/dmgbuild" -s scripts/dmg-settings.py \
  -D app="$APP" \
  -D background=build/dmg-background.tiff \
  -D icon="$APP/Contents/Resources/AppIcon.icns" \
  "Quitty" build/Quitty.dmg
echo "Built build/Quitty.dmg"
