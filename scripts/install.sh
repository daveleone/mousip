#!/bin/sh
# Downloads the latest Mousip release and installs it, without Gatekeeper prompts:
# files downloaded with curl don't get the quarantine flag that browsers add.
#
#   curl -fsSL https://raw.githubusercontent.com/daveleone/mousip/main/scripts/install.sh | sh
set -eu

URL="https://github.com/daveleone/mousip/releases/latest/download/Mousip.zip"
BUNDLE_ID=com.mousip.app

if [ -w /Applications ]; then
    DEST=/Applications
else
    DEST="$HOME/Applications"
    mkdir -p "$DEST"
fi
APP="$DEST/Mousip.app"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading Mousip…"
curl -fL --progress-bar "$URL" -o "$TMP/Mousip.zip"
ditto -x -k "$TMP/Mousip.zip" "$TMP"

pkill -x Mousip 2>/dev/null && sleep 0.5 || true
rm -rf "$APP"
ditto "$TMP/Mousip.app" "$APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

# An ad-hoc signed build gets a new identity every release, so the old Accessibility
# entry no longer matches: clear it and let the app ask again.
if codesign -dv "$APP" 2>&1 | grep -q "Signature=adhoc"; then
    tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
fi

echo "✓ Installed in $APP"
open "$APP"
