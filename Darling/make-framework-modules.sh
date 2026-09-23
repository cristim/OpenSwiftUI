#!/bin/sh
# Give Darling's framework headers Clang module maps so Swift can import them.
# Darling's in-tree SDK ships 125 frameworks' headers and no module maps at all;
# swift-darling's SDK has the module maps but only 17 frameworks. This bridges
# the two: an umbrella-header framework module per framework, built over the
# in-tree headers, searched ahead of them with -F.
# If COCOTRON_ROOT is set, prefer its current headers for Cocotron frameworks.
# This avoids compiling against an older SDK snapshot after a Cocotron update.
set -eu
: "${DARLING_SDK_HEADERS:?in-tree MacOSX.sdk with framework Headers}" "${OUT:?destination .../System/Library/Frameworks}"
D=$DARLING_SDK_HEADERS
for f in "$@"; do
	src=$D/System/Library/Frameworks/$f.framework/Headers
	if [ -n "${COCOTRON_ROOT:-}" ] && [ -f "$COCOTRON_ROOT/$f/include/$f/$f.h" ]; then
		src=$COCOTRON_ROOT/$f/include/$f
	fi
	[ -d "$src" ] || { echo "$f: no headers, skipped"; continue; }
	[ -f "$src/$f.h" ] || { echo "$f: no umbrella header, skipped"; continue; }
	rm -rf "$OUT/$f.framework"
	mkdir -p "$OUT/$f.framework/Headers" "$OUT/$f.framework/Modules"
	cp -a "$src/." "$OUT/$f.framework/Headers/"
	if [ "$f" = OpenGL ]; then
		# gl.h includes glext.h inside extern "C". Keep the extension headers textual;
		# importing them as implicit C++ submodules fails in Swift C++ interop builds.
		cat > "$OUT/$f.framework/Modules/module.modulemap" <<'MM'
framework module OpenGL {
  umbrella header "OpenGL.h"
  textual header "CGLInternal.h"
  textual header "glext.h"
  textual header "internal/khrplatform.h"
  export *
}
MM
	else
		cat > "$OUT/$f.framework/Modules/module.modulemap" <<MM
framework module $f {
  umbrella header "$f.h"
  export *
  module * { export * }
}
MM
	fi
	echo "$f: $(ls "$OUT/$f.framework/Headers" | wc -l) headers"
done
