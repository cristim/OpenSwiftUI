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

# The recorded flag set covers system libraries only. The app-facing frameworks, the
# Objective-C runtime and the Swift runtime come from a built Darling prefix, so the
# undefined set collapses to the sibling reimplementations that still need linking.
PREFIX=${PREFIX:?set PREFIX to a built Darling prefix}
add() {
    local install=$1 rel=$2 cand
    for cand in "$PREFIX$rel" "${rel//\/Versions\/C\//\/Versions\/A\/}"; do
        if [ -f "$cand" ]; then args+=(-dylib_file "$install:$cand"); return; fi
    done
    echo "!! missing in prefix: $install" >&2
}
add /usr/lib/libobjc.A.dylib            /usr/lib/libobjc.A.dylib
add /usr/lib/libdispatch.dylib         /usr/lib/libdispatch.dylib
add /usr/lib/swift/libswiftCore.dylib  /usr/lib/swift/libswiftCore.dylib
add /usr/lib/swift/libswiftObjectiveC.dylib /usr/lib/swift/libswiftObjectiveC.dylib
add /usr/lib/swift/libswiftDispatch.dylib   /usr/lib/swift/libswiftDispatch.dylib
add /usr/lib/swift/libswiftDarwin.dylib     /usr/lib/swift/libswiftDarwin.dylib
add /usr/lib/swift/libswiftCoreFoundation.dylib /usr/lib/swift/libswiftCoreFoundation.dylib
add /usr/lib/swift/libswiftCoreGraphics.dylib   /usr/lib/swift/libswiftCoreGraphics.dylib
add /System/Library/Frameworks/Foundation.framework/Versions/C/Foundation \
    /System/Library/Frameworks/Foundation.framework/Versions/C/Foundation
add /System/Library/Frameworks/AppKit.framework/Versions/C/AppKit \
    /System/Library/Frameworks/AppKit.framework/Versions/C/AppKit
add /System/Library/Frameworks/CoreGraphics.framework/Versions/A/CoreGraphics \
    /System/Library/Frameworks/CoreGraphics.framework/Versions/A/CoreGraphics
add /System/Library/Frameworks/CoreText.framework/Versions/A/CoreText \
    /System/Library/Frameworks/CoreText.framework/Versions/A/CoreText
add /System/Library/Frameworks/QuartzCore.framework/Versions/A/QuartzCore \
    /System/Library/Frameworks/QuartzCore.framework/Versions/A/QuartzCore
add /System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation \
    /System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation

mapfile -t objects < <(find "$OBJ/obj" -name '*.o' | sort)
echo "linking ${#objects[@]} objects -> $OUT"
"$LD" "${args[@]}" -o "$OUT" "${objects[@]}"
echo "== exports"
llvm-nm -gj --defined-only --arch=arm64 "$OUT" | wc -l
