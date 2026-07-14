#!/usr/bin/env bash
#
# package-wimlib.sh — packages wimlib-imagex + its dylibs inside App/Resources
# and makes them self-contained (@executable_path) so the app is distributable.
#
# wimlib is GPLv3. Flint is open source (GPLv3), so packaging the binary
# and running it as a subprocess is perfectly compatible.
#
# Usage:
#   scripts/package-wimlib.sh [BREW_PREFIX] [SIGN_IDENTITY]
#
#   BREW_PREFIX    Homebrew prefix. Defaults to /opt/homebrew (Apple Silicon).
#                  On Intel it's usually /usr/local.
#   SIGN_IDENTITY  Signing identity. Defaults to "-" (ad-hoc, development only).
#                  For distribution: "Developer ID Application: YOUR NAME (TEAMID)".
#
# Prerequisite:  brew install wimlib
#
set -eo pipefail

BREW_PREFIX="${1:-/opt/homebrew}"
IDENTITY="${2:--}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RES_DIR="$ROOT/App/Resources"
BIN_SRC="$BREW_PREFIX/bin/wimlib-imagex"

if [ ! -e "$BIN_SRC" ]; then
  echo "✖ $BIN_SRC not found"
  echo "  Install wimlib first:  brew install wimlib"
  exit 1
fi

mkdir -p "$RES_DIR"
echo "▸ Copying wimlib-imagex to App/Resources…"
cp -L "$BIN_SRC" "$RES_DIR/wimlib-imagex"     # -L follows the symlink to the real binary
chmod u+w "$RES_DIR/wimlib-imagex"

# Recursively rewrites the non-system dylibs to @executable_path and copies them.
# (Compatible with macOS bash 3.2: no associative arrays.)
seen=" "                              # already-processed basenames, surrounded by spaces
queue=("$RES_DIR/wimlib-imagex")
qi=0

deps_of() {
  # Lists dynamic dependencies under the Homebrew prefix or /usr/local (not /usr/lib or /System).
  otool -L "$1" | awk 'NR>1 {print $1}' | grep -E "^($BREW_PREFIX|/usr/local)/" || true
}

echo "▸ Packaging dependent dylibs…"
while [ "$qi" -lt "${#queue[@]}" ]; do
  current="${queue[$qi]}"
  qi=$((qi + 1))
  while IFS= read -r dep; do
    [ -z "$dep" ] && continue
    base="$(basename "$dep")"
    case "$seen" in
      *" $base "*) : ;;               # already copied
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

# Sign (dylibs first, then the binary) with hardened runtime.
echo "▸ Signing (identity: $IDENTITY)…"
shopt -s nullglob
for dylib in "$RES_DIR"/*.dylib; do
  codesign --force --timestamp --options runtime --sign "$IDENTITY" "$dylib"
done
codesign --force --timestamp --options runtime --sign "$IDENTITY" "$RES_DIR/wimlib-imagex"

echo "✓ wimlib packaged in App/Resources."
echo "  Remember to regenerate the project:  xcodegen generate"
