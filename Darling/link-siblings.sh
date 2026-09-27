#!/usr/bin/env bash
# Link the open-source reimplementations SwiftUI depends on into dylibs.
#
# OpenAttributeGraph and OpenRenderBox are the two the SwiftUI objects reference by
# C symbol (_OAG*, _RB*). Their objects already exist from a previous build; this
# only turns them into dylibs with the same install-name shape Darling uses.
#
# usage: link-siblings.sh <prototype workspace> <out dir> <darling prefix>
set -uo pipefail

PROTO=${1:?prototype workspace}
OUT=${2:?out dir}
PREFIX=${3:?darling prefix}
LD=/home/cristi/src/darling/build/src/external/cctools-port/cctools/ld64/src/aarch64-apple-darwin20-ld
SDK=$PROTO/sdk

mkdir -p "$OUT"

# Objects from the prototype's .build directories, laid out per target.
link_one() {
    local name=$1 install=$2 builddir=$3
    [ -d "$builddir" ] || { echo "!! no objects for $name at $builddir"; return 1; }
    mapfile -t objs < <(find "$builddir" -name '*.o' | sort)
    [ ${#objs[@]} -gt 0 ] || { echo "!! $name: no .o under $builddir"; return 1; }
    echo "== $name: ${#objs[@]} objects -> $OUT/$name.dylib"
    "$LD" -dylib -arch arm64 -platform_version macos 26.0 26.0 -syslibroot "$SDK" \
        -install_name "$install" -compatibility_version 1.0.0 -current_version 1.0.0 \
        -L "$PREFIX/usr/lib" -L "$PREFIX/usr/lib/system" -L "$PREFIX/usr/lib/swift" \
        -F "$PREFIX/System/Library/Frameworks" \
        -o "$OUT/$name.dylib" \
        "$PREFIX/usr/lib/libSystem.B.dylib" \
        "$PREFIX/usr/lib/system/"*.dylib \
        "$PREFIX/usr/lib/swift/libswiftCore.dylib" \
        "${objs[@]}" 2>&1 | grep -vE "dwarf|directory not found" | head -20
    [ -f "$OUT/$name.dylib" ] && echo "   ok: $(llvm-nm -gj --defined-only --arch=arm64 "$OUT/$name.dylib" | wc -l) exports"
}

# The Swift half of AttributeGraph calls the C++ half's _OAG* entry points, and the
# C++ half is what defines them, so they have to be one dylib: linked separately the
# Swift objects have nothing to bind the ~52 _OAG* symbols to.
link_attrgraph() {
    local install=/usr/lib/libAttributeGraph.dylib
    mapfile -t objs < <(find "$PROTO/deps/debug/OpenAttributeGraph.build" \
                             "$PROTO/deps/debug/OpenAttributeGraphCxx.build" \
                             "$PROTO/deps/debug/OpenAttributeGraphShims.build" \
                             -name '*.o' 2>/dev/null | sort)
    [ ${#objs[@]} -gt 0 ] || { echo "!! no AttributeGraph objects"; return 1; }
    echo "== libAttributeGraph: ${#objs[@]} objects (Swift + C++ + shims)"
    "$LD" -dylib -arch arm64 -platform_version macos 26.0 26.0 -syslibroot "$SDK" \
        -install_name "$install" -compatibility_version 1.0.0 -current_version 1.0.0 \
        -L "$PREFIX/usr/lib" -L "$PREFIX/usr/lib/system" -L "$PREFIX/usr/lib/swift" \
        -F "$PREFIX/System/Library/Frameworks" \
        -o "$OUT/libAttributeGraph.dylib" \
        "$PREFIX/usr/lib/libSystem.B.dylib" \
        "$PREFIX/usr/lib/system/"*.dylib \
        "$PREFIX/usr/lib/swift/libswiftCore.dylib" \
        $(for c in libc++ libc++abi; do [ -f "$PREFIX/usr/lib/$c.dylib" ] && echo "$PREFIX/usr/lib/$c.dylib"; done) \
        $(for c in libswiftCompatibility51 libswiftCompatibility50 libswiftCompatibilitySpan; do
            [ -f "$PREFIX/usr/lib/swift/$c.dylib" ] && echo "$PREFIX/usr/lib/swift/$c.dylib"
        done) \
        $(for a in libswiftCompatibility56 libswiftCompatibility51 libswiftCompatibility50 \
                    libswiftCompatibilityConcurrency libswiftCompatibilityDynamicReplacements; do
            f=/home/cristi/src/swift-darling/osx-6.3.3/payload/usr/lib/swift/macosx/$a.a
            [ -f "$f" ] && echo "$f"
        done) \
        $(for a in libswiftCompatibilitySpan libswiftCompatibilityPacks; do
            f=/home/cristi/src/swift-darling/osx-6.3.3/payload/usr/lib/swift/macosx/$a.a
            [ -f "$f" ] && echo "$f"
        done) \
        $(for c in libz; do
            for cand in "$PREFIX/usr/lib/$c.dylib" "$PREFIX/usr/lib/$c.1.dylib"; do
                [ -f "$cand" ] && echo "$cand"
            done
        done) \
        "${objs[@]}" 2>&1 | grep -vE "dwarf|directory not found" | head -12
    [ -f "$OUT/libAttributeGraph.dylib" ] &&
        echo "   ok: $(llvm-nm -gj --defined-only --arch=arm64 "$OUT/libAttributeGraph.dylib" | wc -l) exports"
}

link_attrgraph
