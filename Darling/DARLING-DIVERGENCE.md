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
- **Two SDKs are on the header search path at once, and the wrong Foundation wins.** `-F` entries are
  searched before the sysroot's own frameworks, so `#import <Foundation/Foundation.h>` from AppKit
  resolves to the in-tree SDK's Foundation (203 headers), not the curated one that carries the module
  map and API notes (202 headers). Observed in a diagnostic trace, not inferred. This is the
  CryptoKit Foundation trap one level down: the compile is clean and only the ABI or the module
  contents differ. The durable fix is to merge the framework headers into the curated SDK rather than
  stacking two SDKs with `-F`.

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
| `Sources/OpenSwiftUI_SPI/Shims/UIFoundation/NSText.h:27` | `typedef NS_ENUM(NSInteger, NSWritingDirection)` fails with `invalid storage class specifier in function declarator`. **Not root-caused.** `NS_ENUM` is defined and reachable in both SDKs (`NSObjCRuntime.h:251`), so the obvious explanation is wrong; do not assume it is a missing macro. |
| `Sources/OpenSwiftUI_SPI/Shims/UIFoundation/NSAttributedString.h:59` | `NSAttributedStringFormattingOptions` is not declared in Darling's Foundation. |
| `Sources/OpenSwiftUI_SPI/Shims/CoreGraphics/CoreGraphics_Private.h:15` | `cg_nullable` is undefined in Darling's CoreGraphics headers. |
| `Sources/OpenSwiftUI_SPI/Shims/QuartzCore/` | `duplicate interface definition for class 'CAFilter'`. |

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
