#!/usr/bin/env bash
# Link the compiled OpenSwiftUI objects into a real SwiftUI dylib for Darling.
#
# The objects come from build-objects.sh. The dependency closure is expressed with
# ld64 -dylib_file, reusing the flag set the Swift overlay build already records, so
# the result has the same install-name and reexport shape as the other Darling
# frameworks.
#
# usage: link-swiftui.sh <obj dir> <output dylib>
set -euo pipefail

OBJ=${1:?obj dir}
OUT=${2:?output dylib}
LD=/home/cristi/src/darling/build/src/external/cctools-port/cctools/ld64/src/aarch64-apple-darwin20-ld
FLAGS=/home/cristi/src/swift-darling/logs/darling-link-flags.txt
SDK=/home/cristi/src/swift-darling/sdk/MacOSX.sdk
INSTALL_NAME=/System/Library/Frameworks/SwiftUI.framework/Versions/A/SwiftUI

mapfile -t dylib_files < <(python3 - "$FLAGS" <<'EOF'
import re, sys
text = open(sys.argv[1]).read()
line = re.search(r'LINK_FLAGS\s*=\s*(.*)', text, re.S).group(1)
for pair in re.findall(r'-Wl,-dylib_file,(\S+)', line):
    print(pair)
EOF
)

args=(-dylib -arch arm64 -platform_version macos 26.0 26.0 -syslibroot "$SDK"
      -install_name "$INSTALL_NAME" -compatibility_version 1.0.0 -current_version 1.0.0
      -unexported_symbols_list /dev/null)
for pair in "${dylib_files[@]}"; do
    args+=(-dylib_file "$pair")
done

mapfile -t objects < <(find "$OBJ/obj" -name '*.o' | sort)
echo "linking ${#objects[@]} objects -> $OUT"
"$LD" "${args[@]}" -o "$OUT" "${objects[@]}"

echo "== exports"
llvm-nm -gj --defined-only --arch=arm64 "$OUT" | wc -l
