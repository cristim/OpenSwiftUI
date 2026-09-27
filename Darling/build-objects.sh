#!/usr/bin/env bash
# Compile the OpenSwiftUI fork's two targets as one module named SwiftUI, emitting
# object files for linking into a real dylib.
#
# The prior prototype workspace at .scratch-swiftui-fw supplies the inputs (gen-build.py,
# the captured SwiftPM arg lists, the dependency modules, the SDK shims) read-only. All
# outputs go under this session's private output dir. The out dir must be on a
# disk-backed filesystem: gen-build.py writes its arg list unbuffered and silently
# produces an empty one (which swiftc reports as "no input files") if the write fails.
#
# usage: build-objects.sh <out dir>
set -uo pipefail

H=${PROTO_WS:-/home/cristi/src/.scratch-swiftui-fw}
OUT=${1:?out dir}
TC=/home/cristi/src/swift-darling/toolchain-linux/swift-6.3.3-RELEASE-ubuntu24.04-aarch64/usr/bin

export LD_LIBRARY_PATH=/tmp/vd-swiftpm-libs
export TMPDIR="$OUT/tmp" CLANG_MODULE_CACHE_PATH="$OUT/ModuleCache"
mkdir -p "$TMPDIR" "$OUT"

for t in OpenSwiftUICore OpenSwiftUI; do
    python3 "$H/gen-build.py" "$t" "$OUT" || exit 1
    if [ ! -s "$OUT/$t.args" ]; then
        echo "!! $t.args is empty; out dir is probably full" >&2
        exit 1
    fi
    mapfile -t ARGS < "$OUT/$t.args"
    flock -w 3600 /tmp/agent-locks/darling-heavy-build.lock nice -n 10 \
        "$TC/swiftc" "${ARGS[@]}"
    echo "== $t rc=$?"
done
