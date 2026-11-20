#!/usr/bin/env bash
#
# doctor.sh — checks whether this Mac can build, test, sign and run MacControl, and says how to fix what is not.
# Read-only: it changes nothing.

set -uo pipefail

ok()   { printf '  \033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[1;33m!\033[0m %s\n' "$*"; }
bad()  { printf '  \033[1;31m✗\033[0m %s\n' "$*"; }

echo "Toolchain"
if command -v swift >/dev/null 2>&1; then ok "$(swift --version 2>&1 | head -1)"; else bad "swift not found — install Xcode or run: xcode-select --install"; fi
echo "  developer dir: $(xcode-select -p 2>/dev/null || echo none)"

if [[ -d /Applications/Xcode.app && "$(xcode-select -p 2>/dev/null)" != /Applications/Xcode.app/* ]]; then
    warn "Xcode is installed but not selected. Run:  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    warn "(or prefix commands with DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer)"
fi

echo "SwiftPM"
if xcrun --sdk macosx --show-sdk-platform-path >/dev/null 2>&1; then
    ok "xcrun finds the platform path; 'swift build' and 'swift test' can work"
else
    warn "xcrun cannot find the platform path, so SwiftPM fails (build.sh falls back to swiftc)."
    warn "Fix: install Xcode, or reinstall the tools:  sudo rm -rf /Library/Developer/CommandLineTools && xcode-select --install"
fi

echo "Unit tests (XCTest)"
if [[ -d "$(xcode-select -p 2>/dev/null)/Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework" ]]; then
    ok "XCTest present — ./build.sh test will work"
else
    warn "XCTest not found (it ships with Xcode, not with Command Line Tools) — ./build.sh test cannot run here."
fi

echo "Signing (needed for the administrator helper)"
identities="$(security find-identity -v -p codesigning 2>/dev/null | grep -v 'valid identities found' | sed 's/^ *//')"
if [[ -n "${identities}" ]]; then
    ok "signing identities:"; echo "${identities}" | sed 's/^/      /'
    echo "      build with:  SIGN_IDENTITY=\"<identity name>\" ./build.sh"
else
    warn "no signing identity: the app works, but the administrator helper stays unavailable."
    warn "Create a free 'Apple Development' certificate: Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates ▸ +"
fi

echo "This Mac"
echo "  $(sysctl -n hw.model) · macOS $(sw_vers -productVersion) · $(uname -m)"
if [[ "$(uname -m)" != "x86_64" ]]; then warn "Apple Silicon: temperatures and fans are not read through SMC the same way (the project targets Intel)."; fi

echo "Privacy permissions (read-only check)"
if /usr/bin/python3 -c "import os,sys; os.close(os.open('/Library/Application Support/com.apple.TCC/TCC.db', os.O_RDONLY))" 2>/dev/null; then
    ok "this terminal has Full Disk Access (MacControl needs its own grant, see the Permissions screen)"
else
    warn "this terminal has no Full Disk Access (irrelevant for MacControl itself; grant it in the Permissions screen)"
fi
