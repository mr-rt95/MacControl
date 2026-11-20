#!/usr/bin/env bash
#
# build-with-swiftc.sh — fallback build that bypasses SwiftPM.
#
# Some machines have a Command Line Tools installation where SwiftPM cannot run
# (`xcrun: error: unable to lookup item 'PlatformPath'`). The compiler itself still
# works, so this script compiles the same sources with swiftc directly.
#
# Usage: Scripts/build-with-swiftc.sh <output-dir> [debug|release]
# Output: <output-dir>/MacControl, MacControlProbe and MacControlHelper
# Optional: HELPER_INFO_PLIST=<path> overrides the Info.plist embedded into the helper.

set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly OUT_DIR="${1:?usage: build-with-swiftc.sh <output-dir> [debug|release]}"
readonly CONFIGURATION="${2:-release}"
readonly TARGET="$(uname -m)-apple-macos12.0"

flags=(-target "${TARGET}")
if [[ "${CONFIGURATION}" == "release" ]]; then
    flags+=(-O -wmo)
else
    flags+=(-Onone -g)
fi

mkdir -p "${OUT_DIR}"

swift_files() { find "${ROOT_DIR}/Sources/$1" -name '*.swift' | sort; }

# 0. C shim for NVMe SMART (needs compiling; CLibProc is header-only)
clang -c -target "${TARGET}" -O2 -I "${ROOT_DIR}/Sources/CNVMe/include" \
    "${ROOT_DIR}/Sources/CNVMe/CNVMe.c" -o "${OUT_DIR}/CNVMe.o"
rm -f "${OUT_DIR}/libCNVMe.a"
ar rcs "${OUT_DIR}/libCNVMe.a" "${OUT_DIR}/CNVMe.o"

# 1. Core library (module + static archive)
swiftc "${flags[@]}" -parse-as-library -module-name MacControlCore \
    -I "${ROOT_DIR}/Sources/CLibProc/include" -I "${ROOT_DIR}/Sources/CNVMe/include" \
    -emit-module -emit-module-path "${OUT_DIR}/MacControlCore.swiftmodule" \
    -emit-library -static -o "${OUT_DIR}/libMacControlCore.a" \
    $(swift_files MacControlCore)

link=(-I "${OUT_DIR}" -I "${ROOT_DIR}/Sources/CLibProc/include" -I "${ROOT_DIR}/Sources/CNVMe/include"
      -L "${OUT_DIR}" -lMacControlCore -lCNVMe -framework IOKit -framework CoreFoundation)

# 2. Application
swiftc "${flags[@]}" -parse-as-library -module-name MacControl "${link[@]}" \
    $(swift_files MacControl) -o "${OUT_DIR}/MacControl"

# 3. Diagnostic probe
swiftc "${flags[@]}" -module-name MacControlProbe "${link[@]}" \
    $(swift_files MacControlProbe) -o "${OUT_DIR}/MacControlProbe"

# 4. Privileged helper daemon. Its Info.plist (carrying the signing team ID) is embedded in the executable.
readonly HELPER_PLIST="${HELPER_INFO_PLIST:-${ROOT_DIR}/Resources/HelperInfo.plist}"
swiftc "${flags[@]}" -module-name MacControlHelper "${link[@]}" \
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "${HELPER_PLIST}" \
    $(swift_files MacControlHelper) -o "${OUT_DIR}/MacControlHelper"
