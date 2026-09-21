#!/bin/sh
# Stage Sources/OpenSwiftUI_SPI and apply Darling/patches/ to the copy.
#
# Sources/ stays as upstream wrote it so a new upstream release is a rebase rather than a
# conflict, the same reason stage-as-swiftui.py rewrites imports into a staging tree instead
# of editing the files in place. Header changes that are only true for Darling's SDK live in
# Darling/patches/ and are applied here.
#
#   Darling/stage-spi.sh <staging dir>
#
# then point the build at the staged copy rather than at Sources/:
#
#   -Xcc -I<staging dir>/Sources/OpenSwiftUI_SPI
#   -Xcc -fmodule-map-file=<staging dir>/Sources/OpenSwiftUI_SPI/module.modulemap
set -eu

[ $# -eq 1 ] || { echo "usage: $0 <staging dir>" >&2; exit 2; }
dst=$1
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/.." && pwd)

rm -rf "$dst/Sources/OpenSwiftUI_SPI"
mkdir -p "$dst/Sources"

# A patch that half-applies would otherwise leave a tree that still compiles, against
# headers nobody chose. Take the whole staged copy away with it.
trap 'st=$?; [ $st -eq 0 ] || rm -rf "$dst/Sources/OpenSwiftUI_SPI"; exit $st' EXIT

cp -a "$repo/Sources/OpenSwiftUI_SPI" "$dst/Sources/"

n=0
for p in "$here"/patches/*.patch; do
	[ -e "$p" ] || break
	# -F0: no fuzz, so a patch whose context has drifted fails here instead of
	# applying somewhere plausible and wrong.
	patch -p1 -F0 -d "$dst" --no-backup-if-mismatch < "$p"
	n=$((n + 1))
done
echo "staged OpenSwiftUI_SPI -> $dst/Sources/OpenSwiftUI_SPI, applied $n patch(es)"
