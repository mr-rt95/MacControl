#!/usr/bin/env bash
#
# build.sh — builds MacControl and packages it as a macOS .app bundle (with the privileged helper).
#
# Usage:
#   ./build.sh            Release build -> build/MacControl.app
#   ./build.sh debug      Debug build   -> build/MacControl.app
#   ./build.sh test       Run the unit tests only
#   ./build.sh run        Release build, then launch the app from build/
#   ./build.sh install    Release build, install to /Applications (replacing a previous copy), launch it from there.
#                         Use this when the administrator helper is involved: macOS registers the helper from one
#                         app location, and two copies of the app (build/ and /Applications) confuse it.
#
# Signing (optional; see docs/HELPER.md):
#   SIGN_IDENTITY="<certificate name>"   sign with this certificate. An Apple-issued certificate is pinned by its
#                                        Team ID; a self-signed one (Keychain Access ▸ Certificate Assistant) is
#                                        pinned by its SHA-1 hash. Either way the helper trusts only this signer.
#   SIGN_KEYCHAIN=<path>                 look for the certificate in this keychain instead of the default ones
#   TEAM_ID=ABCDE12345                   provide the Team ID explicitly
#
# Without a certificate the app is ad-hoc signed: everything works except the administrator helper,
# which macOS only registers for a properly signed app.
#
# Requirements: Xcode or Command Line Tools (Swift 5.7+).

set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly APP_NAME="MacControl"
readonly HELPER_NAME="MacControlHelper"
readonly BUILD_DIR="${ROOT_DIR}/build"
readonly APP_DIR="${BUILD_DIR}/${APP_NAME}.app"

mode="${1:-release}"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

command -v swift >/dev/null 2>&1 || fail "Swift toolchain not found. Install Xcode or Command Line Tools."

cd "${ROOT_DIR}"

if [[ "${mode}" == "test" ]]; then
    log "Running unit tests"
    swift test
    exit 0
fi

configuration="release"
[[ "${mode}" == "debug" ]] && configuration="debug"

# --- Signer identity (the helper uses it to verify who may talk to it) -----------------------------------
team_id="${TEAM_ID:-}"
cert_hash=""
keychain_args=()
[[ -n "${SIGN_KEYCHAIN:-}" ]] && keychain_args=("${SIGN_KEYCHAIN}")
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    cert_info="$(security find-certificate -c "${SIGN_IDENTITY}" -Z -p "${keychain_args[@]+"${keychain_args[@]}"}" 2>/dev/null || true)"
    [[ -n "${cert_info}" ]] || fail "Certificate '${SIGN_IDENTITY}' not found. List candidates with: security find-identity -p codesigning"
    cert_hash="$(printf '%s\n' "${cert_info}" | awk '/^SHA-1 hash:/ {print $3; exit}')"
    if [[ -z "${team_id}" ]]; then
        # Apple-issued certificates carry the Team ID in the subject's OU; self-signed ones do not.
        team_id="$(printf '%s\n' "${cert_info}" | openssl x509 -noout -subject -nameopt multiline 2>/dev/null \
            | awk -F'= ' '/organizationalUnitName/ {print $2; exit}')"
    fi
fi
# A Team ID is preferred; without one the exact certificate is pinned.
if [[ -n "${team_id}" ]]; then cert_hash=""; fi
readonly team_id cert_hash
signed=false
[[ -n "${team_id}" || -n "${cert_hash}" ]] && signed=true
readonly signed

# --- Build ------------------------------------------------------------------------------------------
helper_plist="${ROOT_DIR}/Resources/HelperInfo.plist"
if [[ "${signed}" == true ]]; then
    helper_plist="${BUILD_DIR}/HelperInfo.plist"
    mkdir -p "${BUILD_DIR}"
    cp "${ROOT_DIR}/Resources/HelperInfo.plist" "${helper_plist}"
    /usr/libexec/PlistBuddy -c "Set :MCSigningTeamID ${team_id}" "${helper_plist}"
    /usr/libexec/PlistBuddy -c "Set :MCSigningCertHash ${cert_hash}" "${helper_plist}"
fi

# SwiftPM is preferred. Some Command Line Tools installations cannot run it (xcrun fails to find the
# platform path), and the signer identity has to be embedded in the helper; both cases use the swiftc script.
if [[ "${signed}" == false ]] && swift package describe >/dev/null 2>&1; then
    log "Building with SwiftPM (${configuration})"
    swift build -c "${configuration}"
    BIN_DIR="$(swift build -c "${configuration}" --show-bin-path)"
else
    log "Building with swiftc (${configuration})"
    BIN_DIR="${BUILD_DIR}/bin"
    HELPER_INFO_PLIST="${helper_plist}" "${ROOT_DIR}/Scripts/build-with-swiftc.sh" "${BIN_DIR}" "${configuration}"
fi
readonly BIN_DIR

# --- Bundle -----------------------------------------------------------------------------------------
log "Assembling ${APP_NAME}.app"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources" "${APP_DIR}/Contents/Library/LaunchDaemons"

cp "${BIN_DIR}/${APP_NAME}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
cp "${BIN_DIR}/${HELPER_NAME}" "${APP_DIR}/Contents/MacOS/${HELPER_NAME}"
cp "${ROOT_DIR}/Resources/com.maccontrol.helper.plist" "${APP_DIR}/Contents/Library/LaunchDaemons/"
cp "${ROOT_DIR}/Resources/Info.plist" "${APP_DIR}/Contents/Info.plist"
cp "${ROOT_DIR}/Resources/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"

if [[ "${signed}" == true ]]; then
    /usr/libexec/PlistBuddy -c "Add :MCSigningTeamID string ${team_id}" "${APP_DIR}/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :MCSigningCertHash string ${cert_hash}" "${APP_DIR}/Contents/Info.plist"
fi

# Localizations (en.lproj, ru.lproj, ...)
for lproj in "${ROOT_DIR}"/Resources/*.lproj; do
    [[ -d "${lproj}" ]] && cp -R "${lproj}" "${APP_DIR}/Contents/Resources/"
done

# --- Signing ----------------------------------------------------------------------------------------
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    if [[ -n "${team_id}" ]]; then log "Signing with '${SIGN_IDENTITY}' (Team ${team_id})"
    else log "Signing with '${SIGN_IDENTITY}' (self-signed, pinned by hash ${cert_hash})"; fi

    # A secure timestamp needs an Apple-issued certificate; a self-signed one skips it.
    timestamp="--timestamp"
    [[ -z "${team_id}" ]] && timestamp="--timestamp=none"
    keychain_flag=()
    [[ -n "${SIGN_KEYCHAIN:-}" ]] && keychain_flag=(--keychain "${SIGN_KEYCHAIN}")

    # Inside-out: the helper first, then the app. Identifiers must match what the helper's requirements expect.
    codesign --force --options runtime "${timestamp}" --identifier "com.maccontrol.helper" "${keychain_flag[@]+"${keychain_flag[@]}"}" \
             --sign "${SIGN_IDENTITY}" "${APP_DIR}/Contents/MacOS/${HELPER_NAME}"
    codesign --force --options runtime "${timestamp}" --identifier "com.maccontrol.app" "${keychain_flag[@]+"${keychain_flag[@]}"}" \
             --entitlements "${ROOT_DIR}/Resources/MacControl.entitlements" \
             --sign "${SIGN_IDENTITY}" "${APP_DIR}"
    codesign --verify --strict "${APP_DIR}"
else
    log "Signing (ad-hoc): the administrator helper stays inactive without a real certificate"
    codesign --force --sign - --identifier "com.maccontrol.helper" "${APP_DIR}/Contents/MacOS/${HELPER_NAME}" >/dev/null
    codesign --force --sign - --identifier "com.maccontrol.app" "${APP_DIR}" >/dev/null
fi

log "Done: ${APP_DIR}"

if [[ "${mode}" == "run" ]]; then
    open "${APP_DIR}"
fi

if [[ "${mode}" == "install" ]]; then
    readonly INSTALLED="/Applications/${APP_NAME}.app"
    log "Installing to ${INSTALLED}"
    pkill -x "${APP_NAME}" 2>/dev/null || true
    sleep 1
    rsync -a --delete "${APP_DIR}/" "${INSTALLED}/"
    # Only one copy may exist: unregister the build copy from Launch Services and remove it.
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "${APP_DIR}" >/dev/null 2>&1 || true
    rm -rf "${APP_DIR}"
    log "Installed. If the helper was registered from another location: Permissions ▸ Remove helper ▸ Install helper."
    open "${INSTALLED}"
fi
