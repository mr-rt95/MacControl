#!/usr/bin/env bash
#
# release.sh — builds MacControl and packages it as a drag-to-install DMG.
#
# Modes:
#   DEVELOPER_ID="Developer ID Application: Name (TEAMID)" NOTARY_PROFILE="maccontrol-notary" ./release.sh
#       Full public release: signed with a Developer ID certificate, notarized by Apple, stapled.
#       Opens on any Mac without warnings. Needs the paid Apple Developer Program.
#
#   SIGN_IDENTITY="Apple Development" ./release.sh --dev-signed
#       Signed with a free Apple Development certificate, NOT notarized. The administrator helper works,
#       but macOS asks the user to confirm the first launch (right-click ▸ Open). Good for GitHub releases.
#
#   ./release.sh --unsigned
#       No certificate. Everything works except the administrator helper; same first-launch confirmation.
#
# One-time setup of the notarization credentials (Developer ID mode only):
#   xcrun notarytool store-credentials "maccontrol-notary" \
#       --apple-id "you@example.com" --team-id TEAMID --password "<app-specific password>"
#
# Output: build/MacControl-<version>.dmg and its .sha256

set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BUILD_DIR="${ROOT_DIR}/build"
readonly APP="${BUILD_DIR}/MacControl.app"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

mode="notarized"
case "${1:-}" in
    --unsigned)   mode="unsigned" ;;
    --dev-signed) mode="dev-signed" ;;
    "")           mode="notarized" ;;
    *)            fail "unknown option '$1' (use --dev-signed, --unsigned, or no option for a notarized release)" ;;
esac

case "${mode}" in
    notarized)
        [[ -n "${DEVELOPER_ID:-}" ]] || fail "DEVELOPER_ID is not set. Use --dev-signed or --unsigned for a build without notarization."
        [[ -n "${NOTARY_PROFILE:-}" ]] || fail "NOTARY_PROFILE is not set (see the header of this script)."
        ;;
    dev-signed)
        [[ -n "${SIGN_IDENTITY:-}" ]] || fail "SIGN_IDENTITY is not set (e.g. SIGN_IDENTITY=\"Apple Development\")."
        ;;
esac

cd "${ROOT_DIR}"
case "${mode}" in
    notarized)  SIGN_IDENTITY="${DEVELOPER_ID}" "${ROOT_DIR}/build.sh" release ;;
    dev-signed) "${ROOT_DIR}/build.sh" release ;;
    unsigned)   env -u SIGN_IDENTITY "${ROOT_DIR}/build.sh" release ;;
esac

readonly VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP}/Contents/Info.plist")"
readonly DMG="${BUILD_DIR}/MacControl-${VERSION}.dmg"

if [[ "${mode}" == "notarized" ]]; then
    log "Notarizing the app (this takes a few minutes)"
    ditto -c -k --keepParent "${APP}" "${BUILD_DIR}/MacControl-notarize.zip"
    xcrun notarytool submit "${BUILD_DIR}/MacControl-notarize.zip" --keychain-profile "${NOTARY_PROFILE}" --wait
    xcrun stapler staple "${APP}"
    rm -f "${BUILD_DIR}/MacControl-notarize.zip"
fi

"${ROOT_DIR}/Scripts/make-dmg.sh" "${APP}" "${DMG}"

if [[ "${mode}" == "notarized" ]]; then
    log "Signing and notarizing the DMG"
    codesign --force --timestamp --sign "${DEVELOPER_ID}" "${DMG}"
    xcrun notarytool submit "${DMG}" --keychain-profile "${NOTARY_PROFILE}" --wait
    xcrun stapler staple "${DMG}"
    spctl --assess --type open --context context:primary-signature --verbose=2 "${DMG}"
fi

( cd "${BUILD_DIR}" && shasum -a 256 "MacControl-${VERSION}.dmg" | tee "MacControl-${VERSION}.dmg.sha256" )
log "Done (${mode}): ${DMG}"
