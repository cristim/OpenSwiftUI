#!/bin/sh
# Census which Clang modules this package's Swift sources import can actually be
# built against Darling's SDK. Seconds per module, versus minutes for a full
# Swift build, so check the Clang side first when a build fails on a module.
#
#   SWIFT_TOOLCHAIN  usr/ of a Swift toolchain (its clang is used)
#   DARLING_SDK      swift-darling's MacOSX.sdk (the one with module maps)
#   DARLING_HEADERS  darling/Developer/.../MacOSX.sdk/System/Library/Frameworks
#   EXTRA_FRAMEWORKS optional: a directory of frameworks to search first
#   EXTRA_CFLAGS     optional: the build's own gates, e.g. the -D flags the package
#                    compiles its shims with. Without them this census cannot reach
#                    UIFoundation_Private or OpenSwiftUI_SPI at all.
#
#   Darling/probe-clang-modules.sh AppKit CoreText QuartzCore ...
set -u
: "${SWIFT_TOOLCHAIN:?}" "${DARLING_SDK:?}" "${DARLING_HEADERS:?}"
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Probe the headers the build actually compiles, which are the staged copy with
# Darling/patches/ applied, not the pristine ones in Sources/.
"$here/stage-spi.sh" "$tmp/stage" >/dev/null || {
	echo "stage-spi.sh failed; not probing pristine headers instead" >&2
	exit 1
}
spi=$tmp/stage/Sources/OpenSwiftUI_SPI
for m in "$@"; do
	printf '%s\t' "$m"
	echo "@import $m;" > "$tmp/probe.m"
	if "$SWIFT_TOOLCHAIN/bin/clang" -target arm64-apple-macosx26.0 -isysroot "$DARLING_SDK" \
		${EXTRA_FRAMEWORKS:+-F "$EXTRA_FRAMEWORKS"} -F "$DARLING_HEADERS" \
		${EXTRA_CFLAGS:-} \
		-Wno-undef-prefix -fmodules -fobjc-arc -fmodules-cache-path="$tmp/cache" \
		-fmodule-map-file="$spi/module.modulemap" \
		-I "$spi" \
		-fmodule-map-file="$here/copenswiftui.modulemap" \
		-I "$repo/Sources/COpenSwiftUI" \
		-fsyntax-only "$tmp/probe.m" >"$tmp/probe.log" 2>&1
	then echo OK
	# Diagnostics start at column 0; clang also echoes source lines that can
	# contain "error:" as an Objective-C selector piece, so anchor the match.
	else echo "FAIL: $(sed -n 's|^[^ ][^ ]*: \(fatal \)\{0,1\}error: ||p' "$tmp/probe.log" | head -1)"
	fi
done
