#!/usr/bin/env bash
#
# build-notarize.sh — signed + notarized Release build for distribution
# OUTSIDE the Mac App Store (the app can't be sandboxed: it needs the raw disk).
#
# Usage:
#   scripts/build-notarize.sh "Developer ID Application: NAME (TEAMID)" TEAMID NOTARY_PROFILE
#
#   NOTARY_PROFILE is created once with:
#     xcrun notarytool store-credentials NOTARY_PROFILE \
#       --apple-id YOUR_APPLE_ID --team-id TEAMID --password APP_SPECIFIC_PASSWORD
#
# Manual prerequisites (one time):
#   1. Have the "Developer ID Application" certificate in the keychain.
#   2. Set your Team ID in Shared/HelperProtocol.swift (HelperConstants.teamID),
#      so the app↔helper XPC signature validation works.
#   3. brew install wimlib  (to package the binary).
#
set -euo pipefail

IDENTITY="${1:?Missing Developer ID Application identity}"
TEAM="${2:?Missing Team ID}"
PROFILE="${3:?Missing notarytool profile}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "▸ 1/6 Packaging signed wimlib…"
scripts/package-wimlib.sh /opt/homebrew "$IDENTITY"

echo "▸ 2/6 Generating project…"
xcodegen generate

echo "▸ 3/6 Building Release (hardened runtime)…"
rm -rf build/dd
xcodebuild -project Flint.xcodeproj -scheme Flint -configuration Release \
  -derivedDataPath build/dd \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  DEVELOPMENT_TEAM="$TEAM" \
  ENABLE_HARDENED_RUNTIME=YES \
  clean build

APP="build/dd/Build/Products/Release/Flint.app"

echo "▸ 4/6 Re-signing embedded helper and app…"
codesign --force --options runtime --timestamp \
  --entitlements Helper/Helper.entitlements --sign "$IDENTITY" \
  "$APP/Contents/MacOS/FlintHelper"
codesign --force --options runtime --timestamp \
  --entitlements App/App.entitlements --sign "$IDENTITY" "$APP"

echo "▸ 5/6 Notarizing…"
mkdir -p build
ZIP="build/Flint.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

echo "▸ 6/6 Stapling…"
xcrun stapler staple "$APP"

echo "✓ Done: $APP notarized and stapled."
echo "  Verify:  spctl -a -vvv \"$APP\""
