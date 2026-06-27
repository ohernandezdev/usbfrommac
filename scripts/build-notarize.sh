#!/usr/bin/env bash
#
# build-notarize.sh — build de Release firmado + notarizado para distribución
# FUERA del Mac App Store (la app no puede ir en sandbox: necesita disco crudo).
#
# Uso:
#   scripts/build-notarize.sh "Developer ID Application: NOMBRE (TEAMID)" TEAMID NOTARY_PROFILE
#
#   NOTARY_PROFILE se crea una vez con:
#     xcrun notarytool store-credentials NOTARY_PROFILE \
#       --apple-id TU_APPLE_ID --team-id TEAMID --password APP_SPECIFIC_PASSWORD
#
# Pasos manuales previos (una vez):
#   1. Tener el certificado "Developer ID Application" en el llavero.
#   2. Poner tu Team ID en Shared/HelperProtocol.swift (HelperConstants.teamID),
#      para que la validación de firma XPC app↔helper funcione.
#   3. brew install wimlib  (para empaquetar el binario).
#
set -euo pipefail

IDENTITY="${1:?Falta la identidad Developer ID Application}"
TEAM="${2:?Falta el Team ID}"
PROFILE="${3:?Falta el perfil de notarytool}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "▸ 1/6 Empaquetando wimlib firmado…"
scripts/package-wimlib.sh /opt/homebrew "$IDENTITY"

echo "▸ 2/6 Generando proyecto…"
xcodegen generate

echo "▸ 3/6 Compilando Release (hardened runtime)…"
rm -rf build/dd
xcodebuild -project WinUSBMac.xcodeproj -scheme WinUSBMac -configuration Release \
  -derivedDataPath build/dd \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  DEVELOPMENT_TEAM="$TEAM" \
  ENABLE_HARDENED_RUNTIME=YES \
  clean build

APP="build/dd/Build/Products/Release/WinUSBMac.app"

echo "▸ 4/6 Re-firmando helper embebido y app…"
codesign --force --options runtime --timestamp \
  --entitlements Helper/Helper.entitlements --sign "$IDENTITY" \
  "$APP/Contents/MacOS/WinUSBMacHelper"
codesign --force --options runtime --timestamp \
  --entitlements App/App.entitlements --sign "$IDENTITY" "$APP"

echo "▸ 5/6 Notarizando…"
mkdir -p build
ZIP="build/WinUSBMac.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

echo "▸ 6/6 Stapling…"
xcrun stapler staple "$APP"

echo "✓ Listo: $APP notarizado y stapleado."
echo "  Verifica:  spctl -a -vvv \"$APP\""
