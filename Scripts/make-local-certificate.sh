#!/usr/bin/env bash
#
# make-local-certificate.sh — creates a free, self-signed code-signing certificate in your login keychain,
# so MacControl (and its administrator helper) can be signed without an Apple account or Xcode.
#
# Usage:  Scripts/make-local-certificate.sh [name]        (default name: "MacControl Local")
# Then:   SIGN_IDENTITY="MacControl Local" ./build.sh run
#
# macOS will ask for your password once, to mark the certificate as trusted for code signing (this is a change
# to your own certificate trust settings, and can be undone in Keychain Access).
# The same steps can be done by hand: see docs/HELPER.md.

set -euo pipefail

readonly NAME="${1:-MacControl Local}"
readonly KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

fail() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

if security find-certificate -c "${NAME}" "${KEYCHAIN}" >/dev/null 2>&1; then
    fail "A certificate named '${NAME}' already exists. Pick another name, or delete it in Keychain Access first."
fi

log "Generating the certificate '${NAME}' (valid 10 years)"
cat > "${work}/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = ${NAME}
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
openssl req -x509 -newkey rsa:2048 -nodes -keyout "${work}/key.pem" -out "${work}/cert.pem" -days 3650 \
    -config "${work}/cert.cnf" >/dev/null 2>&1
openssl pkcs12 -export -inkey "${work}/key.pem" -in "${work}/cert.pem" -out "${work}/id.p12" -passout pass:maccontrol >/dev/null 2>&1

log "Importing into the login keychain"
security import "${work}/id.p12" -k "${KEYCHAIN}" -P maccontrol -T /usr/bin/codesign >/dev/null

log "Trusting it for code signing (macOS will ask for your password)"
security add-trusted-cert -r trustRoot -p codeSign -k "${KEYCHAIN}" "${work}/cert.pem"

log "Done. Check:  security find-identity -v -p codesigning"
echo "Build with:   SIGN_IDENTITY=\"${NAME}\" ./build.sh run"
