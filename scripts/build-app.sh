#!/usr/bin/env bash
# Builds build/Quitty.app. Set UNIVERSAL=1 for an arm64 + x86_64 binary
# (needs full Xcode); CODESIGN_IDENTITY to sign with a real certificate.
set -euo pipefail
cd "$(dirname "$0")/.."

# A plain string, not an array: macOS ships bash 3.2, where an empty array
# trips `set -u`.
ARCH_FLAGS=""
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  ARCH_FLAGS="--arch arm64 --arch x86_64"
fi

# shellcheck disable=SC2086
swift build -c release $ARCH_FLAGS
# shellcheck disable=SC2086
BIN_DIR="$(swift build -c release $ARCH_FLAGS --show-bin-path)"

APP="build/Quitty.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Quitty" "$APP/Contents/MacOS/Quitty"
cp Resources/Info.plist "$APP/Contents/Info.plist"

ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  codesign --force --sign "$CODESIGN_IDENTITY" "$APP"
else
  # Plain ad-hoc signature. Gatekeeper's "Open Anyway" approves an app by its
  # designated requirement, so don't replace the default one.
  codesign --force --sign - "$APP"
fi
codesign --verify --deep --strict --verbose=2 "$APP"
echo "Built $APP"
