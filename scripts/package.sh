#!/bin/zsh
# Packages an already built build/Mousip.app into build/Mousip.zip and build/Mousip.dmg.
#
#   ./build.sh && scripts/package.sh
#
# With SIGN_IDENTITY set, the disk image is signed too (needed to notarize it).
set -euo pipefail
cd "${0:A:h}/.."

APP_NAME=Mousip
APP="build/$APP_NAME.app"
ZIP="build/$APP_NAME.zip"
DMG="build/$APP_NAME.dmg"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

[[ -d "$APP" ]] || { echo "Missing $APP: run ./build.sh first" >&2; exit 1; }
rm -f "$ZIP" "$DMG"

ditto -c -k --keepParent "$APP" "$ZIP"
echo "✓ $ZIP"

# Disk image with the classic "drag to Applications" layout.
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
ditto "$APP" "$staging/$APP_NAME.app"
ln -s /Applications "$staging/Applications"
hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$staging" -fs HFS+ -format UDZO -ov "$DMG"
if [[ "$SIGN_IDENTITY" != "-" ]]; then
    codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"
fi
echo "✓ $DMG"
