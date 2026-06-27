#!/usr/bin/env bash
#
# dogfood.sh — build LOCAL FIRMADO para probar la app de verdad en tu Mac.
#
# Firmar aquí NO es distribuir: es solo para que macOS deje REGISTRAR el helper
# root (SMAppService) que ejecuta el formateo. No notariza ni publica nada.
#
# Qué hace:
#   1. Empaqueta wimlib-imagex + dylibs (si wimlib está instalado) y los firma.
#   2. Compila Release firmado con tu Developer ID + hardened runtime.
#   3. Re-firma helper embebido y app, y verifica la firma.
#   4. Instala la app en /Applications (ubicación estable que SMAppService espera).
#   NUNCA formatea nada: eso lo haces tú desde la app con un USB de prueba.
#
# Uso:  scripts/dogfood.sh
#
set -eo pipefail   # sin 'u' (nounset): evita falsos "unbound variable" en algunos shells

# --- Tu identidad de firma (Team C34D3V8484). Cambia si usas otra cuenta. ---
IDENTITY="Developer ID Application: Omar Jesus Hernandez Bastos (C34D3V8484)"
TEAM="C34D3V8484"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
APP_NAME="WinUSBMac.app"
INSTALL="/Applications/$APP_NAME"

# 1. wimlib (opcional pero necesario para dividir install.wim) ----------------
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
  echo "▸ Empaquetando wimlib firmado desde $PREFIX…"
  scripts/package-wimlib.sh "$PREFIX" "$IDENTITY"
else
  echo "⚠ wimlib NO instalado (brew install wimlib)."
  echo "  La app se construirá y podrás probar Formatear + Copiar, pero la fase"
  echo "  DIVIDIR install.wim fallará con un error claro hasta que instales wimlib."
  rm -f App/Resources/wimlib-imagex App/Resources/*.dylib 2>/dev/null || true
fi

# 2. Generar y compilar firmado ----------------------------------------------
echo "▸ Generando proyecto…"
xcodegen generate

echo "▸ Compilando firmado (Developer ID + hardened runtime)…"
rm -rf build/dd
xcodebuild -project WinUSBMac.xcodeproj -scheme WinUSBMac -configuration Release \
  -derivedDataPath build/dd \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  DEVELOPMENT_TEAM="$TEAM" \
  ENABLE_HARDENED_RUNTIME=YES \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  clean build

APP="build/dd/Build/Products/Release/$APP_NAME"

# 3. Re-firmar helper + app (sella el bundle con hardened runtime) ------------
echo "▸ Re-firmando helper y app…"
# --identifier: un tool sin Info.plist se firma con el nombre del ejecutable
# ("WinUSBMacHelper"); el requisito XPC exige "com.omar.winusbmac.helper".
codesign --force --options runtime --timestamp \
  --identifier com.omar.winusbmac.helper \
  --entitlements Helper/Helper.entitlements --sign "$IDENTITY" \
  "$APP/Contents/MacOS/WinUSBMacHelper"
codesign --force --options runtime --timestamp \
  --entitlements App/App.entitlements --sign "$IDENTITY" "$APP"
echo "▸ Verificando firma…"
codesign --verify --deep --strict --verbose=2 "$APP"

# 4. Instalar en /Applications -----------------------------------------------
echo "▸ Instalando en $INSTALL…"
osascript -e 'tell application "WinUSBMac" to quit' 2>/dev/null || true
pkill -x WinUSBMac 2>/dev/null || true
rm -rf "$INSTALL"
cp -R "$APP" "$INSTALL"

echo
echo "✓ Instalada: $INSTALL"
echo "  Ábrela:  open \"$INSTALL\""
echo "  Si pide aprobar el componente con privilegios:"
echo "    Ajustes del Sistema → General → Elementos de inicio → activa «WinUSB Mac»."
echo "  Logs del helper en otra terminal:"
echo "    log stream --predicate 'process == \"WinUSBMacHelper\"' --info"
