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
prefix_args=()
for pair in "${dylib_files[@]}"; do
    install=${pair%%:*}
    if [ -f "$PREFIX$install" ]; then
        # Keep the install name the objects' library ordinals refer to, but point it
        # at the real implementation instead of the firstpass stub. These are held
        # back rather than appended here, because the prefix map below re-adds the
        # same install names and ld64 honours the FIRST -dylib_file it is given: a
        # stub entry left in place shadows the real library, which is why 83 plain C
        # functions (abort, calloc, CC_SHA1_*) stayed unresolved.
        prefix_args+=(-dylib_file "$install:$PREFIX$install")
        replaced=$((replaced + 1))
    else
        args+=(-dylib_file "$pair")
    fi
done
args+=("${prefix_args[@]}")
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
# lib<name>.dylib along -L/-F paths, which passing the files as inputs does not
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

mapfile -t objects < <(find "$OBJ/obj" -name '*.o' | sort)
echo "linking ${#objects[@]} objects -> $OUT"

# The dependency closure is passed as ordinary link inputs, not as -dylib_file.
# -dylib_file only records which file answers an install name; it does not add the
# file to the symbol table, so an undefined symbol in a library reachable only
# through libSystem.B's re-exports (abort, calloc, CC_SHA1_*, 83 of them) never
# binds. Proven on a two-line repro: -dylib_file alone leaves _tan unresolved,
# and the same library passed as an input resolves it.
#
# libSystem.B and everything under usr/lib/system go in wholesale, because ld64
# walks their re-export chains and demands the whole closure be present.
closure=("$PREFIX/usr/lib/libSystem.B.dylib")
while IFS= read -r f; do
    closure+=("$f")
done < <(find "$PREFIX/usr/lib/system" -maxdepth 1 -name '*.dylib' | sort)
while IFS= read -r f; do
    closure+=("$f")
done < <(find "$PREFIX/usr/lib/swift" -maxdepth 1 -name '*.dylib' | sort)
for name in libobjc.A libdispatch libclosure libsystem_trace; do
    [ -f "$PREFIX/usr/lib/$name.dylib" ] && closure+=("$PREFIX/usr/lib/$name.dylib")
done
while IFS= read -r f; do
    closure+=("$f")
done < <(find "$PREFIX/System/Library/Frameworks" "$PREFIX/System/Library/PrivateFrameworks" \
             -maxdepth 3 -path '*/Versions/*/*' -type f 2>/dev/null | sort)

echo "closure: ${#closure[@]} libraries"
# Both mechanisms are needed, for different reasons.
#   inputs        add the libraries to the symbol table, so their undefined symbols
#                 can bind at all
#   -dylib_file   tell ld64 which file answers a given install name, which is the only
#                 way a dependency nested inside a framework resolves
#                 (ApplicationServices.framework/Versions/A/Frameworks/ATS.framework)
#                 and which keeps a recorded firstpass stub from shadowing a real one
declare -A mapped=()
for f in "${closure[@]}"; do
    id=$(llvm-objdump --macho --dylib-id "$f" 2>/dev/null | tail -1)
    [ -n "$id" ] && mapped["$id"]="$f"
done
for id in "${!mapped[@]}"; do
    args+=(-dylib_file "$id:${mapped[$id]}")
done
echo "install names mapped: ${#mapped[@]}"

"$LD" -dylib -arch arm64 -platform_version macos 26.0 26.0 -syslibroot "$SDK" \
    -install_name "$INSTALL_NAME" -compatibility_version 1.0.0 -current_version 1.0.0 \
    -L "$PREFIX/usr/lib" -L "$PREFIX/usr/lib/system" -L "$PREFIX/usr/lib/swift" \
    -F "$PREFIX/System/Library/Frameworks" -F "$PREFIX/System/Library/PrivateFrameworks" \
    "${args[@]}" \
    -o "$OUT" "${closure[@]}" "${objects[@]}"
echo "== exports"
llvm-nm -gj --defined-only --arch=arm64 "$OUT" | wc -l
