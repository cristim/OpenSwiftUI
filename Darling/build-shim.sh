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
    "$TC/clang" -c "$src" -o "$obj" \
        -target arm64-apple-macosx26.0 -isysroot "$SDK" -fobjc-arc \
        -I "$ROOT/Sources/COpenSwiftUI" \
        -I "$ROOT/Sources/OpenSwiftUI_SPI" \
        -I "$INT/fw/System/Library/Frameworks" \
        -I "$INT/deps/debug" \
        -I "${OPENRENDERBOX_ROOT:-$INT/OpenRenderBox-build}/Sources/OpenRenderBoxCxx/include" \
        -DOPENSWIFTUI_NO_ADAPTIVE_IMAGE_GLYPH \
        -Wno-everything \
        || { echo "!! failed: ${src#$ROOT/}"; fail=$((fail + 1)); }
done
echo "== shim failures: $fail"
find "$OUT/obj/shim" -name '*.o' | wc -l
