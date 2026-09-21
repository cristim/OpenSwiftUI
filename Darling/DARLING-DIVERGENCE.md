# Building OpenSwiftUI as Darling's SwiftUI.framework

Fork of `OpenSwiftUIProject/OpenSwiftUI`, branch `darling`, forked from upstream
`0f791a97a64ac82ded659fd5475876a25e2d6001`.

Goal: a `/System/Library/Frameworks/SwiftUI.framework` for Darling arm64 that exports the exact
mangled symbols macOS apps bind. Swift mangling is a function of declared API plus module name, so
OpenSwiftUICore and OpenSwiftUI must compile as **one** module named `SwiftUI`.

Companion fork: `cristim/OpenAttributeGraph`, branch `darling`, pinned at
`9d4c21c` (upstream `1d8e762338d6447c0b8c98cd08ccf1efca981e82` plus two commits).
Pin by commit, never by branch.

Changes are sorted into **general fixes** (real defects, reproduce outside Darling, worth offering
upstream) and **Darling adaptations** (encode assumptions only true for Darling's SDK).

## Nothing in `Sources/` is patched yet

The single-module merge is done at build time by `Darling/stage-as-swiftui.py`, which copies
`Sources/OpenSwiftUICore` and `Sources/OpenSwiftUI` into a staging tree and rewrites imports. Keeping
it out of `Sources/` keeps the fork rebasable: a new upstream release is a `git rebase`, not a
180-file conflict.

The script does two things:

1. **Strips `import OpenSwiftUICore`** (180 occurrences). Inside one module the cross-target import
   is meaningless. It also removes any `@_spi(...)` attribute lines that decorated the import --
   leaving those behind silently reattaches the attribute to the next declaration, which surfaces far
   away as `unexpected tokens in '#if' body`. Match every spelling: `import`, `package import`,
   `@_spi(X) public import`. Matching only the bare form misses 29 files.
2. **Swaps `import OpenObservation` for `import Observation`** (10 occurrences). Apple's own
   Observation module is the ABI-correct source of `Observable` and `ObservationRegistrar`;
   OpenObservation is its open-source twin. darling-swift already ships `libswiftObservation.dylib`
   with an arm64 slice. None of the symbols AppZapper binds mention Observation, so this is
   ABI-neutral for that binary and removes a third package from the dependency graph.

## Where the remaining work is: Darling's SDK, not this repo

Every blocker found so far is a missing **Clang module** or a missing macro in Darling's SDK, not
missing OpenSwiftUI code.

Darling has two SDKs. `darling/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk` has 125
frameworks' headers and **no module maps at all**. `swift-darling/sdk/MacOSX.sdk` is the Swift-capable
one: 17 frameworks, hand-written module maps and API notes. Swift can only import what the second one
declares.

Proven: adding an `AppKit.framework` with a `Modules/module.modulemap` (`umbrella header "AppKit.h"`)
over the 234 AppKit headers, plus `-F` at the first SDK for the headers AppKit includes, builds the
AppKit Clang module cleanly. Only `-Wno-undef-prefix` is needed: Darling's SDK does not define
`TARGET_OS_WASI`, and `-Wundef-prefix=TARGET_OS_` is an error by default.

`Darling/make-framework-modules.sh` does this for any framework whose headers carry an umbrella.
Done and verified importable: **AppKit, CoreText, QuartzCore, ImageIO, UniformTypeIdentifiers,
OpenGL**.

OpenGL was not on the original list. Adding QuartzCore's module map *broke* AppKit, which had been
importing fine: AppKit includes QuartzCore headers, and modularising QuartzCore surfaced
`CAOpenGLLayer`'s missing `#include <OpenGL/gl.h>`. Giving OpenGL a module map too fixed both.
Modularising a framework can break a framework that already worked, so re-census the whole set after
each addition rather than only the one just added.

Three cannot be done this way: **CoreUI** and **Accessibility** have no headers in Darling at all,
and **CommonCrypto** lives in `usr/include`, so it needs a module in the SDK's own
`usr/include/module.modulemap` rather than a framework module.

**None of the three is actually required**, so the module-map route does not terminate here:

- Every `import CoreUI` is behind `OPENSWIFTUI_LINK_COREUI`, a build flag this build does not set.
- All three `import Accessibility` sites are self-disabling: two behind `#if canImport(Accessibility)`,
  one behind `#if canImport(UIKit)`, which is false on a macOS target.

They appeared in the census because the census greps import lines, which says what a source file
mentions, not what the build needs. Check the guard before treating a census entry as a blocker.

Also in the SDK: `module Darwin` declares no `os` submodule, so `Darwin.os.lock` does not resolve and
`import Observation` fails. `os/lock.h` is present; only the declaration is missing. A separate module
map cannot add it (`parent module must be defined before the submodule`) -- it has to go in the SDK's
own `usr/include/module.modulemap`, which `tools/gen-darwin-module.sh` generates.

Two SDK-wide macro gaps, both hit by ordinary modern Apple headers rather than by anything specific
to this package:

- **visionOS is unknown to the availability macros.** `AvailabilityInternal.h` defines
  `__API_{AVAILABLE,DEPRECATED,UNAVAILABLE}_PLATFORM_*` for macos, ios, watchos, tvos, bridgeos,
  macCatalyst, uikitformac, driverkit and iosmac, and for nothing else, so
  `API_AVAILABLE(..., visionos(1.0))` does not expand and fails to parse.
  `Darling/patch-sdk-visionos.py` adds the six missing definitions. This is general SDK work: any
  header using `visionos(...)` is affected.
- **Two SDKs are on the header search path at once.** `-F` entries are searched before the sysroot's
  own frameworks, so `#import <Foundation/Foundation.h>` from AppKit resolves to the in-tree SDK's
  Foundation, not the curated one that carries the module map and API notes. Observed in a
  diagnostic trace.

  **This is not the cause of the shim-header failures, and collapsing to one search path makes
  things worse.** Tested: copied the 112 frameworks the curated SDK lacks into one directory and
  dropped `-F` at the in-tree SDK, so Foundation could only come from the curated copy. The four
  shim failures were byte-identical, and AppKit and UniformTypeIdentifiers *regressed*
  (`cannot find interface declaration for 'NSLayoutConstraint'` / `'NSItemProvider'`) having built
  cleanly before. The two Foundation header sets turn out to be the same files; the curated SDK adds
  only `Foundation.apinotes`.

  So "merge the headers into one SDK" is an untested recommendation that the one experiment run
  against it contradicts. The working configuration is `-F <sdkext> -F <in-tree SDK>` in that order.
  Whatever the module set is sensitive to, it is header search order, not a duplicated Foundation.

Use `Darling/probe-clang-modules.sh` to re-census this. It costs seconds per module against minutes
for a Swift build, so check the Clang side first.

## Known fork-side fixes still to make

Found by the module census, not yet applied. All are Darling adaptations.

Done: the adaptive image glyph feature (macOS 15 Genmoji) is gated on
`OPENSWIFTUI_NO_ADAPTIVE_IMAGE_GLYPH`, defined for both Clang and Swift. It needs
`<CoreText/CTRunDelegate.h>`, which does not exist anywhere in Darling. Four sites, because a
Clang-only gate leaves the Swift use site dangling: the two shim headers, the `CTAdaptiveImageGlyph`
extension in `CoreText+Private.swift`, and the use site in `Text+NSAttributedString.swift`.

Still open, all in this package's own private shims:

| Header | Problem |
|---|---|
| `Sources/OpenSwiftUI_SPI/Shims/UIFoundation/NSAttributedString.h:59` | `NSAttributedStringFormattingOptions` is not declared in Darling's Foundation. |
| `Sources/OpenSwiftUI_SPI/Shims/UIFoundation/NSStringDrawing.h:44` | `NSAttributedStringKey` is not declared in Darling's Foundation. |
| `Sources/OpenSwiftUI_SPI/Shims/CoreGraphics/CoreGraphics_Private.h:15` | `cg_nullable` is undefined in Darling's CoreGraphics headers. |
| `Sources/OpenSwiftUI_SPI/Shims/QuartzCore/` | `duplicate interface definition for class 'CAFilter'`. |

### `NSText.h:27` -- root-caused, and it was not the macro it looked like

The failure was `invalid storage class specifier in function declarator` on
`typedef NS_ENUM(NSInteger, NSWritingDirection)`, which reads as a broken `NS_ENUM`. It is not.

Falsified first: `NS_ENUM` is defined and reachable (`NSObjCRuntime.h:251` in both SDKs);
preprocessing without `-fmodules` expands it correctly; and a purpose-built module whose header
does `#import <Foundation/Foundation.h>` and then `#ifndef NS_ENUM / #error` builds fine both
textually and modularly, so macro visibility across the module boundary is not the problem either.

The actual cause is **`NS_HEADER_AUDIT_BEGIN`, four lines earlier**, which Darling's SDK does not
define at all (`grep -rl 'define NS_HEADER_AUDIT_BEGIN'` over both SDKs returns nothing, while the
control `NS_ASSUME_NONNULL_BEGIN` is found). Undefined, `NS_HEADER_AUDIT_BEGIN(nullability,
sendability)` parses as a function declarator taking parameters named `nullability` and
`sendability`, and the *next* declaration lands inside it. Clang reports the position where the
parse breaks, not the macro that broke it.

Minimal reproduction, three error lines byte-identical to the real failure:

```objc
#import <Foundation/Foundation.h>
NS_HEADER_AUDIT_BEGIN(nullability, sendability)
typedef NS_ENUM(NSInteger, AuditProbeDirection) { AuditProbeDirectionNatural = -1 };
NS_HEADER_AUDIT_END(nullability, sendability)
```

Adding `-D'NS_HEADER_AUDIT_BEGIN(...)=NS_ASSUME_NONNULL_BEGIN'` and the matching `_END` makes it
parse, and clears the failure in all 15 shim headers that use it. The remaining errors then move
forward to genuinely missing Foundation types, listed above.

The durable fix belongs in `darling-foundation`, `include/Foundation/NSObjCRuntime.h` (submodule
`src/external/foundation`), not in this package. Nothing in the Darling tree uses
`NS_HEADER_AUDIT_*` today, so adding it changes nothing already there.

**Lesson worth keeping: a diagnostic on line N of a header is evidence about the parser's position,
not about line N.** Two plausible hypotheses about the named macro were both wrong.

## Build settings

    -target arm64-apple-macosx26.0 -swift-version 5 -parse-as-library
    -module-name SwiftUI -enable-library-evolution
    -enable-experimental-feature AvailabilityMacro=<each macro in Package.swift>
    -I <OpenAttributeGraph modules>            # OpenAttributeGraph, OpenAttributeGraphShims
    -I <Combine module>                        # OpenCombine built as -module-name Combine
    -I <darling-swift overlays>/out-foundation-min/modules   # Foundation overlay, NOT FoundationEssentials
    -I <darling-swift overlays>/out/modules
    -Xcc -fmodule-map-file=<overlays>/Foundation/shims/module.modulemap
    -Xcc -fmodule-map-file=<OpenCombine>/Sources/COpenCombineHelpers/include/module.modulemap
    -Xcc -fmodule-map-file=Darling/copenswiftui.modulemap       # COpenSwiftUI, publicHeadersPath "."
    -Xcc -fmodule-map-file=Sources/OpenSwiftUI_SPI/module.modulemap
    -Xcc -F<sdk with AppKit.framework> -Xcc -F<darling in-tree SDK frameworks>
    -Xcc -Wno-undef-prefix

**Compile against Darling's Foundation overlay, never Linux FoundationEssentials.** Any signature
mentioning a Foundation protocol mangles the module name into the symbol, and the compile and the link
are both clean when it is wrong; only dyld notices.

## Checked and clear: the canImport self-import trap

Compiling sources as module `SwiftUI` makes `#if canImport(SwiftUI)` true inside those sources, which
silently collapses a guarded file to `@_exported import SwiftUI` and produces a module that
re-exports itself. It is invisible to the compiler and invisible at load, and shows up only in a
symbol diff. swift-crypto hit exactly this with all 91 of its `canImport(CryptoKit)` files.

`Sources/OpenSwiftUI` and `Sources/OpenSwiftUICore` contain **zero** occurrences of
`canImport(SwiftUI)`, so this build is not affected. The three in the repo are in
`OpenSwiftUIBridge` and `OpenSwiftUIExtension`, which are not compiled here. Re-check this if either
target is ever added to the staged set; the fix is an extra build-flag term in each guard.

## Not measured yet

The symbol diff. Nothing here says how many of the 487 symbols AppZapper binds at the SwiftUI ordinal
this build actually exports. A clean compile is not coverage: the CryptoKit probe produced correct type
names, a clean compile and a clean link, and dyld still would not bind. Do not quote a coverage number
before `llvm-nm --defined-only` on the object has been diffed against the demanded list.

## Licence

Upstream is MIT (`LICENSE`), retained unchanged.
