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

# The recorded flag set maps the system libraries to their *_firstpass stubs, which
# exist so an overlay can link before the runtime is built and which do not export the
# real implementations. ld64 prefers an explicit -dylib_file over any -L search, so
# where a built prefix provides the library, drop the recorded entry and let the
# search path find the real one.

PREFIX=${PREFIX:?set PREFIX to a built Darling prefix}
replaced=0
for pair in "${dylib_files[@]}"; do
    install=${pair%%:*}
    if [ -f "$PREFIX$install" ]; then
        # Keep the install name the objects' library ordinals refer to, but point it
        # at the real implementation instead of the firstpass stub.
        [ -n "${REPOINT:-}" ] && args+=(-dylib_file "$install:$PREFIX$install"); [ -n "${REPOINT:-}" ] || args+=(-dylib_file "$pair"); continue
        replaced=$((replaced + 1))
    else
        args+=(-dylib_file "$pair")
    fi
done
echo "repointed $replaced recorded system entries at the prefix copies"

# The recorded flag set covers system libraries only. The app-facing frameworks, the
# Objective-C runtime and the Swift runtime come from a built Darling prefix, so the
# undefined set collapses to the sibling reimplementations that still need linking.

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
add /System/Library/Frameworks/OpenGL.framework/Versions/A/Libraries/libGL.dylib \
    /System/Library/Frameworks/OpenGL.framework/Versions/A/Libraries/libGL.dylib
add /System/Library/Frameworks/OpenGL.framework/Versions/A/Libraries/libGLU.dylib \
    /System/Library/Frameworks/OpenGL.framework/Versions/A/Libraries/libGLU.dylib

# The objects carry autolink entries recorded by -module-link-name (swiftCore,
# swiftDispatch, swiftDarwin, ...). ld64 resolves those by searching for
# lib<name>.dylib along -L/-F paths, which the -dylib_file map above does not
# satisfy, so the runtime has to be findable by name too.
args+=(-L "$PREFIX/usr/lib" -L "$PREFIX/usr/lib/system" -L "$PREFIX/usr/lib/swift")
# Both levels: autolink resolves a framework by name against the parent, while a
# dependency inside a framework (OpenGL.framework/Versions/A/Libraries/libGL.dylib)
# is only found from the framework directory itself.
args+=(-F "$PREFIX/System/Library/Frameworks" -F "$PREFIX/System/Library/PrivateFrameworks")
while IFS= read -r fw; do
    args+=(-F "$fw")
done < <(find "$PREFIX/System/Library/Frameworks" "$PREFIX/System/Library/PrivateFrameworks" \
             -maxdepth 1 -mindepth 1 -name '*.framework' -type d 2>/dev/null | sort)

# Map every library the prefix provides by its own install name. ld64 resolves a
# dependency by install name and will not search for nested paths such as
# ApplicationServices.framework/Versions/A/Frameworks/ATS.framework, so the whole
# closure has to be present in the map. Reading LC_ID_DYLIB is one llvm-objdump per
# image, so it runs in parallel and is cached in $OBJ/prefix-map.
mapfile -t prefix_files < <(find "$PREFIX/usr/lib" "$PREFIX/System/Library/Frameworks" \
    "$PREFIX/System/Library/PrivateFrameworks" -type f 2>/dev/null \
    | grep -E '\.dylib$|/Versions/[A-Z]/[^/]+$' | sort)
if [ ! -s "$OBJ/prefix-map" ]; then
    printf '%s\n' "${prefix_files[@]}" | xargs -P 8 -I{} sh -c \
        'id=$(llvm-objdump --macho --dylib-id "{}" 2>/dev/null); [ -n "$id" ] && printf "%s\t%s\n" "$id" "{}"' \
        > "$OBJ/prefix-map"
fi
while IFS=$'\t' read -r id path; do
    [ -n "$id" ] && args+=(-dylib_file "$id:$path")
done < "$OBJ/prefix-map"
echo "prefix map: $(wc -l < "$OBJ/prefix-map") install names"

mapfile -t objects < <(find "$OBJ/obj" -name '*.o' | sort)
echo "linking ${#objects[@]} objects -> $OUT"
"$LD" "${args[@]}" -o "$OUT" "${objects[@]}"
echo "== exports"
llvm-nm -gj --defined-only --arch=arm64 "$OUT" | wc -l
