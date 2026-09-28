#!/usr/bin/env bash
# Compile OpenRenderBox's C++ layer into objects and link libRenderBox.dylib.
#
# The SwiftUI objects reference 24 _RB* entry points (RBPath*, RBPathStorage*,
# RBUUIDInitFromHash, RBColorModeWorkingColorSpace). The prototype workspace has the
# sources but no compiled objects: deps/debug/OpenRenderBox.build is empty, so nothing
# was ever produced for it. The symbols land in a dylib with the same install-name
# shape the other Darling libraries use, and the SwiftUI link picks it up from $SIB.
#
# Built out of tree: the sources are read from the OpenRenderBox checkout and every
# object goes under the caller's output dir, so that repository is not written to.
#
# usage: build-renderbox.sh <OpenRenderBox root> <out dir> <darling prefix> <sdk>
set -uo pipefail

RB=${1:?OpenRenderBox root}
OUT=${2:?out dir}
PREFIX=${3:?darling prefix}
SDK=${4:?sdk}
LD=/home/cristi/src/darling/build/src/external/cctools-port/cctools/ld64/src/aarch64-apple-darwin20-ld
TC=/home/cristi/src/swift-darling/toolchain-linux/swift-6.3.3-RELEASE-ubuntu24.04-aarch64/usr/bin

OBJ="$OUT/obj/renderbox"
mkdir -p "$OBJ" "$OUT/ModuleCache" "$OUT/tmp"
export CLANG_MODULE_CACHE_PATH="$OUT/ModuleCache" TMPDIR="$OUT/tmp"
export LD_LIBRARY_PATH=${LD_LIBRARY_PATH:+$LD_LIBRARY_PATH:}/home/cristi/.local/share/agent-tmp/quartzcore/swiftpm-libs

mapfile -t srcs < <(find "$RB/Sources/OpenRenderBoxCxx" -type f \
    \( -name '*.cpp' -o -name '*.mm' -o -name '*.m' -o -name '*.c' \) | sort)

# The Color layer needs three extended-range color-space constants that Darling's
# CoreGraphics does not export (kCGColorSpaceExtendedLinearDisplayP3,
# kCGColorSpaceITUR_2100_PQ and a third), so linking it in would fail the whole
# dylib. Everything SwiftUI actually binds is the Path and UUID surface, so the
# Color sources are left out rather than stubbed: a wrong colorspace is worse than
# an absent one, and adding the constants to CoreGraphics is the real fix.
if [ -z "${RB_INCLUDE_COLOR:-}" ]; then
    mapfile -t kept < <(printf '%s\n' "${srcs[@]}" | grep -v '/Color/')
    [ ${#kept[@]} -lt ${#srcs[@]} ] &&
        echo "== excluding ${#srcs[@]} - ${#kept[@]} Color sources (set RB_INCLUDE_COLOR=1 to include)"
    srcs=("${kept[@]}")
fi

echo "compiling ${#srcs[@]} RenderBox sources"

fail=0
for s in "${srcs[@]}"; do
    o="$OBJ/$(echo "${s#$RB/Sources/}" | tr '/' '_' | sed 's/\.[a-z]*$/.o/')"
    case "$s" in
        *.mm) std=(-x objective-c++) ;;
        *.cpp) std=(-x c++ -std=c++20) ;;
        *) std=() ;;
    esac
    # This SDK snapshot is written for the Swift Clang importer, not for standalone C:
    #   CF_BRIDGED_TYPE / CG_BRIDGED_TYPE are importer attributes, not C macros, and
    #     Apple's own headers do not define them, so clang parses them literally and
    #     every `typedef struct CF_BRIDGED_TYPE(id) X *XRef;` breaks
    #   CGWindowLevel.h uses COREGRAPHICS_EXPORT without importing
    #     CoreGraphicsExport.h, where it is defined
    #   <experimental/optional> is gone from the payload's libc++, so
    #     $RB_COMPAT aliases it to std::optional
    # Modules are left off: with -fmodules each header becomes its own module boundary,
    # so the -include below no longer reaches them and the same errors come back.
    "$TC/clang++" -c "$s" -o "$o" \
        -target arm64-apple-macosx26.0 -isysroot "$SDK" \
        -fobjc-arc -fno-objc-arc-exceptions \
        '-DCF_BRIDGED_TYPE(...)=' '-DCG_BRIDGED_TYPE(...)=' \
        -DOPENRENDERBOX_CF_CGTYPES=1 \
        -include "$SDK/System/Library/Frameworks/CoreGraphics.framework/Headers/CoreGraphicsExport.h" \
        -I "$RB/Sources/OpenRenderBoxCxx/include" \
        -I "$RB/Sources/OpenRenderBoxShims/include" \
        ${RB_COMPAT:+-I "$RB_COMPAT"} \
        -I "$PREFIX/System/Library/Frameworks" \
        "${std[@]}" \
        -Wno-everything || { echo "!! failed: ${s#$RB/}"; fail=$((fail + 1)); }
done
echo "== RenderBox compile failures: $fail   objects: $(find "$OBJ" -name '*.o' | wc -l)"

mapfile -t objs < <(find "$OBJ" -name '*.o' | sort)
[ ${#objs[@]} -gt 0 ] || exit 1
echo "== linking libRenderBox.dylib from ${#objs[@]} objects"
"$LD" -dylib -arch arm64 -platform_version macos 26.0 26.0 -syslibroot "$SDK" \
    -install_name /usr/lib/libRenderBox.dylib \
    -compatibility_version 1.0.0 -current_version 1.0.0 \
    -L "$PREFIX/usr/lib" -L "$PREFIX/usr/lib/system" -F "$PREFIX/System/Library/Frameworks" \
    -o "$OUT/libRenderBox.dylib" \
    "$PREFIX/usr/lib/libSystem.B.dylib" "$PREFIX/usr/lib/system/"*.dylib \
    $([ -f "$PREFIX/usr/lib/libc++.dylib" ] && echo "$PREFIX/usr/lib/libc++.dylib" "$PREFIX/usr/lib/libc++abi.dylib") \
    $(for f in CoreFoundation CoreGraphics CoreText AppKit QuartzCore; do
        b="$PREFIX/System/Library/Frameworks/$f.framework/Versions/A/$f"
        [ -f "$b" ] && echo "$b"
      done) \
    $(for c in libswiftCore libswiftObjectiveC libswiftDispatch libswiftDarwin libswiftCoreFoundation libswiftCoreGraphics; do
        [ -f "$PREFIX/usr/lib/swift/$c.dylib" ] && echo "$PREFIX/usr/lib/swift/$c.dylib"
      done) \
    "${objs[@]}" 2>&1 | grep -vE "dwarf|directory not found" | head -12
[ -f "$OUT/libRenderBox.dylib" ] &&
    echo "   ok: $(llvm-nm -gj --defined-only --arch=arm64 "$OUT/libRenderBox.dylib" | wc -l) exports"
