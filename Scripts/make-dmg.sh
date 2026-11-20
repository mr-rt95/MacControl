#!/usr/bin/env bash
#
# make-dmg.sh — packs MacControl.app into a drag-to-install disk image.
#
# Usage: Scripts/make-dmg.sh <path/to/MacControl.app> <output.dmg>
#
# The window layout (icon positions, background) is set through Finder, which needs one-time permission for the
# terminal app to control Finder. If that is unavailable, the DMG is still created, just without the nice layout.

set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly APP="${1:?usage: make-dmg.sh <MacControl.app> <output.dmg>}"
readonly OUTPUT="${2:?usage: make-dmg.sh <MacControl.app> <output.dmg>}"
readonly VOLUME="MacControl"
readonly BACKGROUND="${ROOT_DIR}/Resources/dmg-background.png"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
[[ -d "${APP}" ]] || { echo "error: ${APP} not found" >&2; exit 1; }

work="$(mktemp -d)"
staging="${work}/staging"
raw="${work}/raw.dmg"
trap 'hdiutil detach "/Volumes/${VOLUME}" -force >/dev/null 2>&1 || true; rm -rf "${work}"' EXIT

log "Preparing the image contents"
mkdir -p "${staging}/.background"
ditto "${APP}" "${staging}/MacControl.app"
ln -s /Applications "${staging}/Applications"
[[ -f "${BACKGROUND}" ]] && cp "${BACKGROUND}" "${staging}/.background/background.png"

# Make sure no old volume with the same name is mounted.
hdiutil detach "/Volumes/${VOLUME}" -force >/dev/null 2>&1 || true

log "Creating the image"
size_mb=$(( $(du -sm "${staging}" | cut -f1) + 40 ))
hdiutil create -srcfolder "${staging}" -volname "${VOLUME}" -fs HFS+ -format UDRW -size "${size_mb}m" -ov "${raw}" >/dev/null
hdiutil attach "${raw}" -readwrite -noverify -noautoopen >/dev/null

log "Arranging the window (Finder)"
layout='
tell application "Finder"
    tell disk "'"${VOLUME}"'"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 860, 520}
        set theOptions to the icon view options of container window
        set arrangement of theOptions to not arranged
        set icon size of theOptions to 112
        try
            set background picture of theOptions to file ".background:background.png"
        end try
        set position of item "MacControl.app" of container window to {170, 200}
        set position of item "Applications" of container window to {490, 200}
        update without registering applications
        delay 2
        close
    end tell
end tell'
# Finder scripting can hang on a permission prompt: give it a limited time.
osascript -e "${layout}" >/dev/null 2>&1 &
osa_pid=$!
for _ in $(seq 1 60); do kill -0 "${osa_pid}" 2>/dev/null || break; sleep 1; done
if kill -0 "${osa_pid}" 2>/dev/null; then kill "${osa_pid}" 2>/dev/null || true; echo "warning: Finder layout timed out (permission prompt?); continuing without it" >&2; fi

sync
hdiutil detach "/Volumes/${VOLUME}" >/dev/null 2>&1 || { sleep 2; hdiutil detach "/Volumes/${VOLUME}" -force >/dev/null; }

log "Compressing"
rm -f "${OUTPUT}"
hdiutil convert "${raw}" -format UDZO -imagekey zlib-level=9 -o "${OUTPUT}" >/dev/null
log "Done: ${OUTPUT} ($(du -h "${OUTPUT}" | cut -f1))"
