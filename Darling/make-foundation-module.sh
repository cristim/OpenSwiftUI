#!/bin/sh
# Give the overlay a MODULAR Foundation, ahead of Darling's in-tree SDK on -F.
#
# Without this, AppKit's `#import <Foundation/Foundation.h>` finds a Foundation.framework
# that has no module map, so Clang pulls the whole Foundation header set *textually* into
# module AppKit. The decls then belong to module AppKit, not Foundation, and two things
# that Swift keys off the owning module stop working: Foundation.apinotes is not consulted
# (NSURLSession no longer imports as URLSession), and `import AppKit` -- an internal import
# under InternalImportsByDefault -- becomes the only import that exposes them, so they
# cannot appear in a package or public signature. Verified with `clang -cc1 -module-file-info`
# on the AppKit pcm: it listed CoreGraphics, CoreText, QuartzCore ... and no Foundation.
#
# The headers come from swift-darling's curated SDK because that is the copy that carries
# Foundation.apinotes; the two header sets are otherwise the same files.
#
#   CURATED_SDK  swift-darling's MacOSX.sdk
#   OUT          the overlay's .../System/Library/Frameworks
set -eu
: "${CURATED_SDK:?swift-darling's MacOSX.sdk (the copy with Foundation.apinotes)}" \
  "${OUT:?destination .../System/Library/Frameworks}"

src=$CURATED_SDK/System/Library/Frameworks/Foundation.framework/Headers
[ -f "$src/Foundation.apinotes" ] || { echo "no Foundation.apinotes in $src" >&2; exit 1; }

rm -rf "$OUT/Foundation.framework"
mkdir -p "$OUT/Foundation.framework/Headers" "$OUT/Foundation.framework/Modules"
cp -a "$src/." "$OUT/Foundation.framework/Headers/"

# A directory umbrella, not `umbrella header "Foundation.h"`: 50 of the 202 headers are not
# reachable from Foundation.h, NSLayoutConstraint.h and NSNumber.h among them. With a header
# umbrella those 50 are in the module's directory but in no module, so `#import
# <Foundation/NSLayoutConstraint.h>` from AppKit imports a Foundation that does not declare
# the class -- the `cannot find interface declaration for 'NSLayoutConstraint'` that made
# earlier attempts at a modular Foundation look impossible.
#
# Two headers cannot be in any module and are excluded so they stay textual. Both are
# unreachable from Foundation.h, so nothing had ever compiled them and neither bug is new:
#   NSMutableCharacterSet.h:1  #import <Foundation/NSCharactrSet.h>   (misspelt, no such file)
#   NSSerializer.h:4           duplicate interface definition for class 'NSDeserializer'
cat > "$OUT/Foundation.framework/Modules/module.modulemap" <<'MM'
framework module Foundation [extern_c] [system] {
  umbrella "Headers"
  exclude header "NSMutableCharacterSet.h"
  exclude header "NSSerializer.h"
  export *
}
MM
echo "Foundation: $(ls "$OUT/Foundation.framework/Headers" | wc -l) headers, modular"
