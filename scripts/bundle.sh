#!/bin/zsh
# Assemble build/Brouillon.app a partir du binaire SwiftPM (.build/<config>/Brouillon).
# La version vient de VERSION. Signature ad hoc par defaut ;
# CODESIGN_IDENTITY="Developer ID Application: ..." pour une vraie signature.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-debug}"
APP_NAME="Brouillon"
BIN="$ROOT/.build/$CONFIG/$APP_NAME"
APP="$ROOT/build/$APP_NAME.app"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
IDENTITY="${CODESIGN_IDENTITY:--}"

[ -x "$BIN" ] || { echo "$BIN introuvable : la compilation a echoue ?" >&2; exit 1; }
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
# Bundles de ressources SwiftPM, s'il y en a.
for b in "$ROOT"/.build/"$CONFIG"/*.bundle(N); do
  [ -d "$b" ] && cp -R "$b" "$APP/Contents/Resources/"
done
sed -e "s/\$(EXECUTABLE_NAME)/$APP_NAME/g" \
    -e 's/$(PRODUCT_BUNDLE_IDENTIFIER)/fr.vialet.brouillon/g' \
    -e 's/$(DEVELOPMENT_LANGUAGE)/fr/g' \
    "$ROOT/$APP_NAME/Resources/Info.plist" > "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
if [ -f "$ROOT/$APP_NAME/Resources/AppIcon.icns" ]; then
  cp "$ROOT/$APP_NAME/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi
SIGN_OPTS=()
[ "$IDENTITY" != "-" ] && SIGN_OPTS=(--options runtime --timestamp)
codesign --force --sign "$IDENTITY" "${SIGN_OPTS[@]}" \
  --entitlements "$ROOT/$APP_NAME/Resources/$APP_NAME.entitlements" "$APP" 2>&1 | grep -v "replacing existing signature" || true
echo "-> $APP"
