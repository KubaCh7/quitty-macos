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

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  codesign --force --sign "$CODESIGN_IDENTITY" "$APP"
else
  # Ad-hoc signatures change with every build, which makes macOS forget the
  # Accessibility permission after each update. Pinning the designated
  # requirement to the bundle ID lets the permission carry over.
  BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' Resources/Info.plist)"
  codesign --force --sign - --requirements "=designated => identifier \"$BUNDLE_ID\"" "$APP"
fi
codesign --display --requirements - "$APP"
echo "Built $APP"
