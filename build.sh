#!/bin/zsh
# Builds Mousip and creates build/Mousip.app.
#
#   ./build.sh           build only
#   ./build.sh run       build and launch from build/
#   ./build.sh install   build, copy to /Applications and launch
#
# Signing: ad-hoc by default. macOS ties the Accessibility permission to the binary's hash,
# so after every rebuild "run"/"install" reset the permission and the app asks for it again.
# With a stable signing certificate (SIGN_IDENTITY="Certificate name" ./build.sh install)
# the permission survives rebuilds and the reset is skipped.
set -euo pipefail
cd "${0:A:h}"

APP_NAME=Mousip
BUNDLE_ID=com.mousip.app
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP="build/$APP_NAME.app"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID" "$APP"
echo "✓ $APP"

launch() {
    pkill -x "$APP_NAME" 2>/dev/null && sleep 0.5 || true
    if [[ "$SIGN_IDENTITY" == "-" ]]; then
        tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
    fi
    open "$1"
}

case "${1:-}" in
    run)
        launch "$APP"
        ;;
    install)
        ditto "$APP" "/Applications/$APP_NAME.app"
        echo "✓ /Applications/$APP_NAME.app"
        launch "/Applications/$APP_NAME.app"
        ;;
    "") ;;
    *)
        echo "Usage: $0 [run|install]" >&2
        exit 1
        ;;
esac
