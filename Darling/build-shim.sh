#!/usr/bin/env bash
# Compile the COpenSwiftUI / OpenSwiftUI_SPI C and Objective-C shim into objects
# that link-swiftui.sh folds into the SwiftUI dylib.
#
# These are the definitions the two Swift targets reference but do not themselves
# provide: the OpenSwiftUICorePlatform*/View*/Shadow*/Color* platform layer, the
# AppleInternal helpers, the protocol descriptors, the QuartzCore and CoreGraphics
# private SPI, and the localization entry points.
#
# The UIKit overlays are excluded: Darling has no UIKit, and the iOSSupport path is
# the last item in the plan. Anything that turns out to be reachable only from
# UIKit code stays unresolved until then.
#
# usage: build-shim.sh <out dir> <fork root>
set -uo pipefail

OUT=${1:?out dir}
ROOT=${2:?fork root}
SDK=${PROTO_WS:-/home/cristi/src/.scratch-swiftui-fw}/sdk
TC=/home/cristi/src/swift-darling/toolchain-linux/swift-6.3.3-RELEASE-ubuntu24.04-aarch64/usr/bin
INT=/home/cristi/src/.scratch-swiftui-fw

mkdir -p "$OUT/obj/shim" "$OUT/ModuleCache" "$OUT/tmp"
export CLANG_MODULE_CACHE_PATH="$OUT/ModuleCache"
export TMPDIR="$OUT/tmp"

mapfile -t sources < <(find "$ROOT/Sources/COpenSwiftUI" "$ROOT/Sources/OpenSwiftUI_SPI" \
    -type f \( -name '*.c' -o -name '*.m' -o -name '*.mm' \) \
    | grep -vE '/(UIKit|Testing_Swizzles|UIKitMac)/' | sort)

echo "compiling ${#sources[@]} shim sources"
fail=0
for src in "${sources[@]}"; do
    obj="$OUT/obj/shim/$(echo "${src#$ROOT/Sources/}" | tr '/' '_' | sed 's/\.[cm]*$/.o/')"
    # Only the sources that spell @import need Clang modules turned on. Enabling it
    # for the whole set is a net loss: it makes the module map's umbrella headers
    # shadow the ones included directly, which breaks 17 files that compile fine
    # without it (48 objects with it scoped, 32 with it global).
    modflags=()
    # The @import may be in the source or in a header it pulls in:
    # OpenSwiftUICoreTextGraphicsContextProvider.m has no @import itself, but its own
    # header does (`@import UIFoundation_Private`), so checking only the .m leaves
    # modules disabled and every type from that header unresolved.
    #
    # Only Objective-C and Objective-C++ sources are considered. Turning modules on for
    # a .c file makes Foundation's NSObjCRuntime.h a module boundary, and the
    # CF_BRIDGED_TYPE-using typedefs in it then fail to parse: 51 objects with the
    # narrow test, 50 with a blanket one.
    case "$src" in
        *.c) ;;
        *) if grep -q '@import' "$src" 2>/dev/null ||
             grep -rql '@import' "$(dirname "$src")"/*.h 2>/dev/null; then
               modflags=(-fmodules)
           fi ;;
    esac
    # CGPath+OpenSwiftUI.m uses ORBPath, a C++ type, from an Objective-C file.
    # clang would not see it compiled as plain Objective-C, so anything reaching for
    # ORBPath is built as Objective-C++.
    case "$src" in
        *.m) if grep -qE '\bORB[A-Za-z]*\b' "$src" 2>/dev/null; then stdflags=(-x objective-c++); else stdflags=(); fi ;;
        *) stdflags=() ;;
    esac
    # ORBPath.h and its siblings are gated on OPENRENDERBOX_CF_CGTYPES, which is
    # never defined anywhere, so without it the whole RenderBox surface is invisible
    # and CGPath+OpenSwiftUI.m cannot see ORBPath.
    orbflags=()
    grep -rqE '\bORB[A-Za-z]*\b' "$src" 2>/dev/null && orbflags=(-DOPENRENDERBOX_CF_CGTYPES=1)
    # CoreGraphicsExport.h is deliberately NOT pre-included. Doing so pulls the
    # unmodularised SDK CoreGraphics headers in ahead of the fw/ tree, and AppKit's
    # NSLayoutConstraint category then has no base class to attach to ("cannot find
    # interface declaration for 'NSLayoutConstraint'"). DARLING-DIVERGENCE.md records
    # that exact diagnostic as fixed by using the modularised tree throughout, which is
    # what -F on fw/ does. The CG_BRIDGED_TYPE defines above are what this file needed
    # from the SDK headers, and they are enough on their own.
    "$TC/clang" -c "$src" -o "$obj" \
        -target arm64-apple-macosx26.0 -isysroot "$SDK" -fobjc-arc \
        '-DCF_BRIDGED_TYPE(...)=' '-DCG_BRIDGED_TYPE(...)=' \
        -I "$ROOT/Sources/COpenSwiftUI" \
        -I "$ROOT/Sources/OpenSwiftUI_SPI" \
        -I "$INT/fw/System/Library/Frameworks" \
        -F "$INT/fw/System/Library/Frameworks" \
        -F "$INT/fw/System/Library/Frameworks/Foundation.framework" \
        -I "$INT/deps/debug" \
        -I "${OPENRENDERBOX_ROOT:-$INT/OpenRenderBox-build}/Sources/OpenRenderBoxCxx/include" \
        ${RB_COMPAT:+-I "$RB_COMPAT"} \
        -Xclang -fmodule-map-file="$ROOT/Sources/OpenSwiftUI_SPI/module.modulemap" \
        "${modflags[@]}" "${stdflags[@]}" "${orbflags[@]}" \
        -DOPENSWIFTUI_NO_ADAPTIVE_IMAGE_GLYPH \
        -Wno-everything \
        || { echo "!! failed: ${src#$ROOT/}"; fail=$((fail + 1)); }
done
echo "== shim failures: $fail"
find "$OUT/obj/shim" -name '*.o' | wc -l
