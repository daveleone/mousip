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
# the permission survives rebuilds and the reset is skipped. A real identity also enables the
# hardened runtime and a secure timestamp, both required for notarization.
#
# Optional environment variables (used by the GitHub Actions release workflow):
#   ARCHS="arm64 x86_64"   build a universal binary (needs Xcode, not just the Command Line Tools)
#   VERSION=1.2.0          CFBundleShortVersionString
#   BUILD_NUMBER=42        CFBundleVersion
set -euo pipefail
cd "${0:A:h}"

APP_NAME=Mousip
BUNDLE_ID=com.mousip.app
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP="build/$APP_NAME.app"

swift_args=(-c release)
for arch in ${=ARCHS:-}; do
    swift_args+=(--arch "$arch")
done
swift build "${swift_args[@]}"
BIN_DIR="$(swift build "${swift_args[@]}" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
if [[ -n "${VERSION:-}" ]]; then
    plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
fi
if [[ -n "${BUILD_NUMBER:-}" ]]; then
    plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"
fi

codesign_args=(--force --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID")
if [[ "$SIGN_IDENTITY" != "-" ]]; then
    codesign_args+=(--options runtime --timestamp)
fi
codesign "${codesign_args[@]}" "$APP"
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
