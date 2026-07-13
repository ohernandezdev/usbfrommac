#!/usr/bin/env bash
#
# dogfood.sh — SIGNED LOCAL build to test the app for real on your Mac.
#
# Signing here is NOT distribution: it's only so macOS lets you REGISTER the root
# helper (SMAppService) that runs the formatting. It does not notarize or publish anything.
#
# What it does:
#   1. Packages wimlib-imagex + dylibs (if wimlib is installed) and signs them.
#   2. Builds a signed Release with your Developer ID + hardened runtime.
#   3. Re-signs the embedded helper and app, and verifies the signature.
#   4. Installs the app in /Applications (stable location that SMAppService expects).
#   It NEVER formats anything: you do that yourself from the app with a test USB.
#
# Usage:  scripts/dogfood.sh
#
set -eo pipefail   # without 'u' (nounset): avoids false "unbound variable" in some shells

# --- Your signing identity (Team C34D3V8484). Change it if you use another account. ---
IDENTITY="Developer ID Application: Omar Jesus Hernandez Bastos (C34D3V8484)"
TEAM="C34D3V8484"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
APP_NAME="UsbFromMac.app"
INSTALL="/Applications/$APP_NAME"

# 1. wimlib (optional but required to split install.wim) ----------------------
WIMLIB=""
PREFIX=""
for p in /opt/homebrew/bin/wimlib-imagex /usr/local/bin/wimlib-imagex; do
  if [ -x "$p" ]; then
    WIMLIB="$p"
    PREFIX="$(dirname "$(dirname "$p")")"
    break
  fi
done
if [ -n "$WIMLIB" ]; then
  echo "▸ Packaging signed wimlib from $PREFIX…"
  scripts/package-wimlib.sh "$PREFIX" "$IDENTITY"
else
  echo "⚠ wimlib NOT installed (brew install wimlib)."
  echo "  The app will build and you'll be able to test Format + Copy, but the"
  echo "  SPLIT install.wim phase will fail with a clear error until you install wimlib."
  rm -f App/Resources/wimlib-imagex App/Resources/*.dylib 2>/dev/null || true
fi

# 2. Generate and build signed -----------------------------------------------
echo "▸ Generating project…"
xcodegen generate

echo "▸ Building signed (Developer ID + hardened runtime)…"
rm -rf build/dd
xcodebuild -project UsbFromMac.xcodeproj -scheme UsbFromMac -configuration Release \
  -derivedDataPath build/dd \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  DEVELOPMENT_TEAM="$TEAM" \
  ENABLE_HARDENED_RUNTIME=YES \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  clean build

APP="build/dd/Build/Products/Release/$APP_NAME"

# 3. Re-sign helper + app (seals the bundle with hardened runtime) ------------
echo "▸ Re-signing helper and app…"
# --identifier: a tool without an Info.plist is signed with the executable's name
# ("UsbFromMacHelper"); the XPC requirement demands "com.omarhernandez.usbfrommac.helper".
codesign --force --options runtime --timestamp \
  --identifier com.omarhernandez.usbfrommac.helper \
  --entitlements Helper/Helper.entitlements --sign "$IDENTITY" \
  "$APP/Contents/MacOS/UsbFromMacHelper"
codesign --force --options runtime --timestamp \
  --entitlements App/App.entitlements --sign "$IDENTITY" "$APP"
echo "▸ Verifying signature…"
codesign --verify --deep --strict --verbose=2 "$APP"

# 4. Install in /Applications ------------------------------------------------
echo "▸ Installing in $INSTALL…"
osascript -e 'tell application "UsbFromMac" to quit' 2>/dev/null || true
pkill -x UsbFromMac 2>/dev/null || true
rm -rf "$INSTALL"
cp -R "$APP" "$INSTALL"

echo
echo "✓ Installed: $INSTALL"
echo "  Open it:  open \"$INSTALL\""
echo "  If it asks you to approve the privileged component:"
echo "    System Settings → General → Login Items → enable «USB from Mac»."
echo "  Helper logs in another terminal:"
echo "    log stream --predicate 'process == \"UsbFromMacHelper\"' --info"
