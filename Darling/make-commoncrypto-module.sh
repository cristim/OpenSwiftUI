#!/bin/sh
# Emit a Clang module map for CommonCrypto.
#
# CommonCrypto ships headers but no module: it lives in usr/include, and every one of its
# 25 headers is `exclude header`-ed from the SDK's Darwin module (gen-darwin-module.sh
# excludes everything outside the Darwin umbrella's include closure), so canImport
# (CommonCrypto) is false and CC_SHA1_Update cannot be reached. The declaration is there,
# at usr/include/CommonCrypto/CommonDigest.h.
#
# It cannot be a framework module (wrong location) and cannot be a submodule of Darwin
# (Darwin excludes the headers), so it is its own top-level module, passed to the compiler
# with -Xcc -fmodule-map-file=<this file's output>.
#
#   SDK  the sysroot whose usr/include/CommonCrypto to modularise
#   OUT  directory to write commoncrypto.modulemap into
set -eu
: "${SDK:?sysroot with usr/include/CommonCrypto}" "${OUT:?destination directory}"

umbrella=$SDK/usr/include/CommonCrypto/CommonCrypto.h
[ -f "$umbrella" ] || { echo "no $umbrella" >&2; exit 1; }

mkdir -p "$OUT"
# Absolute path: the map is generated next to the build, not next to the headers, and
# module-map-relative lookup would not reach the SDK from there.
cat > "$OUT/commoncrypto.modulemap" <<MM
module CommonCrypto [system] [extern_c] {
  umbrella header "$umbrella"
  export *
}
MM
echo "CommonCrypto: $OUT/commoncrypto.modulemap"
