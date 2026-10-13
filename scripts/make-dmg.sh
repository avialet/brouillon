#!/bin/zsh
# Fabrique build/Brouillon-X.Y.Z.dmg et son checksum a partir de build/Brouillon.app.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Brouillon"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
APP="$ROOT/build/$APP_NAME.app"
DMG="$ROOT/build/$APP_NAME-$VERSION.dmg"
STAGE="$ROOT/build/dmg-stage"

[ -d "$APP" ] || { echo "build/$APP_NAME.app introuvable : lancez scripts/bundle.sh release" >&2; exit 1; }
BUILT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
[ "$BUILT" = "$VERSION" ] || { echo "$APP_NAME.app est en $BUILT, pas $VERSION : relancez bundle.sh" >&2; exit 1; }

rm -rf "$STAGE" "$DMG" "$DMG.sha256"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Brouillon $VERSION" -srcfolder "$STAGE" -ov -format UDZO -fs HFS+ "$DMG" >/dev/null
rm -rf "$STAGE"
hdiutil verify "$DMG" >/dev/null
(cd "$ROOT/build" && shasum -a 256 "$APP_NAME-$VERSION.dmg" > "$APP_NAME-$VERSION.dmg.sha256")
echo "-> $DMG"
cat "$DMG.sha256"
