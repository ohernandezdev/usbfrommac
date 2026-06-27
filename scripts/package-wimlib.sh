#!/usr/bin/env bash
#
# package-wimlib.sh — empaqueta wimlib-imagex + sus dylibs dentro de App/Resources
# y los hace autocontenidos (@executable_path) para que la app sea distribuible.
#
# wimlib es GPLv3. WinUSB Mac es open source (GPLv3), así que empaquetar el binario
# y ejecutarlo como subproceso es perfectamente compatible.
#
# Uso:
#   scripts/package-wimlib.sh [BREW_PREFIX] [SIGN_IDENTITY]
#
#   BREW_PREFIX    Prefijo de Homebrew. Por defecto /opt/homebrew (Apple Silicon).
#                  En Intel suele ser /usr/local.
#   SIGN_IDENTITY  Identidad de firma. Por defecto "-" (ad-hoc, solo para desarrollo).
#                  Para distribución: "Developer ID Application: TU NOMBRE (TEAMID)".
#
# Requisito previo:  brew install wimlib
#
set -eo pipefail

BREW_PREFIX="${1:-/opt/homebrew}"
IDENTITY="${2:--}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RES_DIR="$ROOT/App/Resources"
BIN_SRC="$BREW_PREFIX/bin/wimlib-imagex"

if [ ! -e "$BIN_SRC" ]; then
  echo "✖ No se encontró $BIN_SRC"
  echo "  Instala wimlib primero:  brew install wimlib"
  exit 1
fi

mkdir -p "$RES_DIR"
echo "▸ Copiando wimlib-imagex a App/Resources…"
cp -L "$BIN_SRC" "$RES_DIR/wimlib-imagex"     # -L sigue el symlink al binario real
chmod u+w "$RES_DIR/wimlib-imagex"

# Reescribe recursivamente las dylibs no-system a @executable_path y las copia.
# (Compatible con bash 3.2 de macOS: sin arrays asociativos.)
seen=" "                              # basenames ya procesados, rodeados de espacios
queue=("$RES_DIR/wimlib-imagex")
qi=0

deps_of() {
  # Lista dependencias dinámicas bajo el prefijo de Homebrew o /usr/local (no /usr/lib ni /System).
  otool -L "$1" | awk 'NR>1 {print $1}' | grep -E "^($BREW_PREFIX|/usr/local)/" || true
}

echo "▸ Empaquetando dylibs dependientes…"
while [ "$qi" -lt "${#queue[@]}" ]; do
  current="${queue[$qi]}"
  qi=$((qi + 1))
  while IFS= read -r dep; do
    [ -z "$dep" ] && continue
    base="$(basename "$dep")"
    case "$seen" in
      *" $base "*) : ;;               # ya copiado
      *)
        cp -f "$dep" "$RES_DIR/$base"
        chmod u+w "$RES_DIR/$base"
        install_name_tool -id "@executable_path/$base" "$RES_DIR/$base"
        seen="$seen$base "
        queue+=("$RES_DIR/$base")
        echo "   + $base"
        ;;
    esac
    install_name_tool -change "$dep" "@executable_path/$base" "$current"
  done < <(deps_of "$current")
done

# Firma (dylibs primero, luego el binario) con hardened runtime.
echo "▸ Firmando (identidad: $IDENTITY)…"
shopt -s nullglob
for dylib in "$RES_DIR"/*.dylib; do
  codesign --force --timestamp --options runtime --sign "$IDENTITY" "$dylib"
done
codesign --force --timestamp --options runtime --sign "$IDENTITY" "$RES_DIR/wimlib-imagex"

echo "✓ wimlib empaquetado en App/Resources."
echo "  Recuerda regenerar el proyecto:  xcodegen generate"
