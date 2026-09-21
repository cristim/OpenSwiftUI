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

Still missing the same way, each needing the same treatment: **CoreText, QuartzCore, CoreUI,
Accessibility, ImageIO, CommonCrypto, UniformTypeIdentifiers**.

Also in the SDK: `module Darwin` declares no `os` submodule, so `Darwin.os.lock` does not resolve and
`import Observation` fails. `os/lock.h` is present; only the declaration is missing. A separate module
map cannot add it (`parent module must be defined before the submodule`) -- it has to go in the SDK's
own `usr/include/module.modulemap`, which `tools/gen-darwin-module.sh` generates.

Use `Darling/probe-clang-modules.sh` to re-census this. It costs seconds per module against minutes
for a Swift build, so check the Clang side first.

## Known fork-side fixes still to make

Found by the module census, not yet applied. All are Darling adaptations.

| Header | Problem |
|---|---|
| `Sources/OpenSwiftUI_SPI/Shims/UIFoundation/NSAdaptiveImageGlyph.h` | imports `<CoreText/CTRunDelegate.h>`, which does not exist anywhere in Darling. Its one Swift use site is `Text+NSAttributedString.swift:349`; both need the same gate. |
| `Sources/OpenSwiftUI_SPI/Shims/CoreText/Private/CTAdaptiveImageGlyph.h` | `API_AVAILABLE(... visionos(2.0))` does not parse; Darling's `Availability.h` has no `visionos`. |
| `Sources/OpenSwiftUI_SPI/Shims/CoreGraphics/CoreGraphics_Private.h` | `cg_nullable` is undefined in Darling's CoreGraphics headers. |
| `Sources/OpenSwiftUI_SPI/Shims/QuartzCore/...` | `duplicate interface definition for class 'CAFilter'`. |

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

## Not measured yet

The symbol diff. Nothing here says how many of the 487 symbols AppZapper binds at the SwiftUI ordinal
this build actually exports. A clean compile is not coverage: the CryptoKit probe produced correct type
names, a clean compile and a clean link, and dyld still would not bind. Do not quote a coverage number
before `llvm-nm --defined-only` on the object has been diffed against the demanded list.

## Licence

Upstream is MIT (`LICENSE`), retained unchanged.
