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

## The overlay rule (read this before adding a framework)

Darling has two SDKs. `darling/Developer/.../MacOSX.sdk` has 125 frameworks' headers and **no module
maps at all**. `swift-darling/sdk/MacOSX.sdk` is the Swift-capable one: 17 frameworks, hand-written
module maps and API notes. Swift can only import what the second declares, so the build puts an
overlay directory ahead of both:

    -Xcc -F <overlay> -Xcc -F <in-tree SDK>      # in that order

> **Frameworks the curated SDK does NOT have get a module map in the overlay.**
> **Frameworks it already has (Foundation, CoreGraphics) go into the overlay as headers only, with
> no `Modules/` directory.**

This is a predictive rule, not a preference, and it has two named failure signatures:

| Break the rule | Symptom |
|---|---|
| give CoreGraphics a module map | `cyclic dependency in module 'CoreGraphics': CoreGraphics -> Foundation -> CoreGraphics` |
| give Foundation a module map | `cannot find interface declaration for 'NSLayoutConstraint'` when importing AppKit |

It also explains an experiment that looked sensible and failed: collapsing to a single framework
search path regressed AppKit and UniformTypeIdentifiers from clean to broken. The cause was never
*which* Foundation was found -- the two header sets are the same files -- but whether Foundation
resolved as a Clang **module** or as textual headers. Both failing configurations had it modular;
the working one does not.

With the rule followed, all nine Clang modules the build needs import cleanly: AppKit, CoreText,
QuartzCore, COpenSwiftUI, OpenSwiftUI_SPI, UIFoundation_Private, CoreText_Private,
CoreGraphics_Private and QuartzCore_Private.

`Darling/probe-clang-modules.sh` re-runs this census in seconds. Re-run it over the **whole** set
after each change, never just the framework you touched: adding QuartzCore's module map broke AppKit,
which had been importing fine, by surfacing `CAOpenGLLayer`'s missing `#include <OpenGL/gl.h>`.

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

  The mechanism turned out to be narrower than "two SDKs", and it is now understood: **AppKit breaks
  whenever Foundation resolves as a Clang *module* rather than as textual headers.** Both failing
  configurations had a modular Foundation; the working one does not. So the rule for the overlay
  directory is:

  > Frameworks the curated SDK does **not** have get a module map. Frameworks it already has
  > (Foundation, CoreGraphics) go into the overlay as **headers only** -- no `Modules/` directory.

  Giving CoreGraphics a module map produces `cyclic dependency in module 'CoreGraphics': CoreGraphics
  -> Foundation -> CoreGraphics`, which is why the curated SDK never modularised it. Giving
  Foundation one produces `cannot find interface declaration for 'NSLayoutConstraint'` in AppKit.
  With both as headers-only in the overlay and `-F <overlay> -F <in-tree SDK>` in that order, all of
  AppKit, CoreText, QuartzCore and four of the five private shim modules build.

Use `Darling/probe-clang-modules.sh` to re-census this. It costs seconds per module against minutes
for a Swift build, so check the Clang side first.

## Known fork-side fixes still to make

Found by the module census, not yet applied. All are Darling adaptations.

Done: the adaptive image glyph feature (macOS 15 Genmoji) is gated on
`OPENSWIFTUI_NO_ADAPTIVE_IMAGE_GLYPH`, defined for both Clang and Swift. It needs
`<CoreText/CTRunDelegate.h>`, which does not exist anywhere in Darling. Four sites, because a
Clang-only gate leaves the Swift use site dangling: the two shim headers, the `CTAdaptiveImageGlyph`
extension in `CoreText+Private.swift`, and the use site in `Text+NSAttributedString.swift`.

Done, and both are general fixes rather than Darling adaptations:

- **`Shims/CoreGraphics/CoreGraphics_Private.h:15`** wrote `float cg_nullable *headroom`. The
  qualifier belongs after the `*`; before it, clang rejects it as applying to the pointee. Line 18 of
  the same file already has it the right way round, so this is a typo, and it is wrong on any
  toolchain with a real `cg_nullable`, not only on Darling. **Upstreamable, not yet offered:** no PR
  has been opened against OpenSwiftUI. Filing into a third party's repository is an outward-facing
  action on someone else's project and is the repository owner's call to make, not something to do
  as a side effect of a build fix. The write-up is here so it is ready if that call is yes.

- **`Package.swift:328` makes `LIBRARY_EVOLUTION=1` unreachable in non-Darwin mode.** The guard is
  `if libraryEvolutionCondition && !openCombineCondition && !swiftLogCondition`, and both
  `openCombineCondition` and `swiftLogCondition` default to `!buildForDarwinPlatform` (lines 166-167).
  So with `BUILD_FOR_DARWIN_PLATFORM=0` the condition is false and `-enable-library-evolution` is
  never passed, **whatever `LIBRARY_EVOLUTION` is set to**. The env var appears to be honoured
  (`libraryEvolutionCondition` reads it) and then is overridden by two unrelated terms. That matters
  beyond configuration tidiness: `Tj` protocol witness dispatch thunks are emitted only under library
  evolution, so a build that silently loses the flag silently loses symbols an ABI consumer may bind.
  **Upstreamable, not yet offered**, for the same reason as the `cg_nullable` typo above.
- **`Shims/QuartzCore/CAFilterPrivate.h`** declared `@interface CAFilter` unconditionally. It is
  private on Apple's platforms, which is why the shim declares it, but **Darling's QuartzCore exposes
  it publicly** in `QuartzCore/CAFilter.h`, and redeclaring it there is a hard error. Guarded on
  `!__has_include(<QuartzCore/CAFilter.h>)`, which needs no Darling-specific flag. Worth saying
  plainly because it reads as a Darling bug and is not one: Darling is being *more* generous than
  Apple here, and the shim assumed Apple's privacy.

- **`Shims/QuartzCore/CoreAnimation_Private.h` and `.m`** declare a category on `CADisplayLink`,
  a class Darling's QuartzCore does not have, so the category has nothing to attach to and the whole
  module fails. Gated on `OPENSWIFTUI_NO_CADISPLAYLINK`. Darling adaptation, and the *only* Swift
  caller (`UIHostingViewBase.swift:905`) is on the UIKit path, which this build does not compile.

### `CAFilter` and `CADisplayLink` look like the same problem and are not

Both are "a declaration that clashes with, or is missing from, Darling's QuartzCore", and they get
different constructs on purpose:

- `CAFilter` -> `#if !__has_include(<QuartzCore/CAFilter.h>)`. The predicate asks about a header
  **Darling demonstrably ships** and that can be checked right here. It is a statement about the SDK
  in hand.
- `CADisplayLink` -> an explicit build flag. `__has_include(<QuartzCore/CADisplayLink.h>)` would be a
  **guess about Apple's header layout**, which nobody here can check without a mounted macOS volume.
  Guess wrong and the category silently disappears on Apple, where nothing traces the loss back. The
  flag fails the other way: always compiled on Apple, explicitly off on Darling, and greppable.

Same construct, different epistemic footing. Narrow the flag to `__has_include` once someone can
check the spelling against a real SDK; the comment in the header says so.

### One symptom was two independent defects

`cg_nullable` produced a single error, and it had **two** causes that would each have produced it:
the macro was missing from Darling's `CGBase.h`, *and* this package placed the qualifier on the wrong
side of the `*`. Fixing only the SDK would have left an error that looked exactly like the fix had
not worked, and the natural next move -- doubting the SDK fix -- would have been wrong. When a fix
does not move a symptom, consider that the symptom has more than one cause before assuming the fix
failed.

### The SDK side: five gaps, all filed as separate PRs

Every one of these is a declaration Darling's SDK lacks that a recent-SDK header needs. None is
specific to this package, each was reproduced minimally before filing, and none changes anything
already in the Darling tree, because nothing there uses them.

| Gap | Repo | PR |
|---|---|---|
| `visionos` unknown to the availability macros | darling | #101 |
| `NS_HEADER_AUDIT_BEGIN` / `_END` | darling-foundation | #35 |
| `NSAttributedStringKey`, `NSAttributedStringFormattingOptions` | darling-foundation | #36 |
| `cg_nullable` | darling-cocotron | #121 |
| `CA_EXTERN`, `CALayerContentsFormat`, `CALayerContentsFilter` | darling-cocotron | #122 |

`NSAttributedStringFormattingOptions` is declared with **no members, deliberately**: its bit values
are not publicly derivable, and a fabricated bit would compile cleanly and then misformat at runtime,
whereas nothing declared makes any use of an option a compile error naming the option. See #36 for
the full reasoning, including why it is a plain typedef (a memberless `NS_OPTIONS` is not legal C).

One SDK gap is **not** filed: `CADisplayLink` is a missing *class*, not a macro or typedef, and
stubbing it would be inventing API surface. It is handled fork-side instead, above.

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

## Handover: the wall at 75, and the cascade correction that makes it bigger

**The count is 75 distinct missing names, and it is conditioned on an unmerged PR.** It was measured
with darling-cocotron **#124 at `239faa6c`**, which is open and not an ancestor of cocotron master
(`9d1c81ac`). Against master the Foundation to CoreGraphics to Foundation cycle returns and the
AppKit Clang module fails with `redefinition of 'NSRectEdge'`. Both states were reproduced, so this
is a dependency with a commit in it, not a caveat. Re-derive the number if #124 changes or lands.

Trajectory: 103 -> 97 -> 83 -> 75. The SDK header corpus was byte-identical to its source across
that whole span, so the deltas are attributable to the changes made, not to the tree moving.

### Correction: the CoreGraphics members are NOT a cascade

An earlier census said 32 of 57 names were cascades, and that "more than a quarter of the wall
clears when CoreGraphics does". **That was wrong and the optimistic version should not be
inherited.**

CoreGraphics types did clear: all ten of `CGPoint`, `CGRect`, `CGSize`, `CGAffineTransform`,
`CGColor`, `CGColorSpace`, `CGDataConsumer`, `CGImage`, `CGLineCap`, `CGLineJoin`. **Not one of the
fifteen members went with them.**

```
import CoreGraphics; import Foundation
r.minX  ->  error: value of type 'CGRect' has no member 'minX'
```

`minX`, `maxX`, `midX`, `midY`, `minY`, `maxY`, `width`, `height`, `isNull`, `isInfinite`,
`standardized`, `offsetBy`, `applying`, `intersection`, `contains` are **Swift extensions from
Apple's CoreGraphics overlay**, not C struct fields. Darling's overlay defines none of them
(`grep -c "extension CGRect"` returns 0). The type comes from C; the members come from Swift.
Fixing the type could never have fixed them.

They were classified as cascades because they are *spelled* as members of a missing type. That is
the trap: **a missing member of a present type is its own category, not a downstream effect.** The
five CALayer members (`contentsScale`, `allowsEdgeAntialiasing`, `contentsFormat`, `contentsCenter`,
`isOpaque`) are the same shape -- `CALayer.h` exists and does not declare them.

Net effect: 20 names move from "clears for free" to real work. The wall is more real than the
cascade framing suggested.

### The six unexplained: four mechanisms proposed and disproved

`NSCoder`, `NSNumber`, `NSMutableAttributedString`, `NSUserActivity`, `Scanner`, `URLSession` each
resolve in isolation, resolve under their own file's exact import set, and still fail in the full
881-file build. Do not attach a fifth mechanism without evidence; these four were tested and
disproved:

1. **Missing from Foundation.** No: each resolves under a plain `import Foundation`.
2. **Framework re-export.** Files importing only AppKit or QuartzCore do lose Swift Foundation, and
   that explained ten *other* names -- but these six resolve under `import AppKit` alone too.
3. **Value versus type position.** No: `Scanner(string:)` resolves in value position. (`URLSession.shared`
   fails differently, because Darling declares it as a method -- a separate real bug.)
4. **The file's own import set.** No: rebuilding `Foundation` + `OpenSwiftUI_SPI` +
   `UIFoundation_Private` still resolves `Scanner`, with the control failing in the same run.

One unread clue: `Scanner` and `URLSession` were not failing before the CoreGraphics module landed
and are after. That is a correlation, not a mechanism.

## Where this run stopped, and why

The build gets through every Clang module and into Swift type-checking, then stops on **2,961
errors naming 114 distinct missing types**. They are not OpenSwiftUI gaps. They are Darling's Swift
overlays.

Checked directly against the overlay interfaces rather than inferred:

| Type | In Darling's overlay? |
|---|---|
| `CGSize`, `CGPoint`, `CGRect`, `CGAffineTransform`, `CGColor`, `CGImage`, `CGColorSpace` | no |
| `AttributedString`, `Bundle`, `RunLoop`, `UserDefaults`, `Thread`, `NSCoder`, `FormatStyle` | no |

Darling's Foundation overlay says so itself: "Intentionally partial: String, Array, Dictionary and
Set bridging only". The CoreGraphics overlay does not declare the CG value types at all.

**Do not close this gap by stubbing the 114 types.** A `CGSize` invented here produces a framework
that links and then lays out wrongly, which is worse than one that does not build, and nothing at
runtime would point back at the stub.

## Measured: the CoreGraphics half is mostly solved, and the Foundation half is mostly a rename

Two configurations were built and their missing-name sets differenced.

| | distinct missing names | total errors |
|---|---|---|
| Darwin path (default) | 114 | 2,961 |
| non-Darwin CG stack | **103** | 2,736 |

Solved by switching to OpenCoreGraphics/OpenQuartzCore: `CGPoint`, `CGRect`, `CGImage`, `CGLineCap`,
`CGLineJoin`, the five `CATransform3D*` functions, `IOSurfaceRef`, `NSAttributedString`. One name
(`bounds`) appears only in the new set, and the single remaining `CGSize` hit is in a file that does
not import CoreGraphics -- both are cascades. In isolation `CGPoint`, `CGRect`, `CGSize` and
`CGFloat` all resolve through `OpenCoreGraphicsShims`.

`OpenCoreGraphics`, `OpenQuartzCore` and both shims build cleanly for `arm64-apple-macosx26.0` with
library evolution, 18 files, zero errors. One flag has to be dropped: the non-Darwin path's
`-isystem Sources/SwiftCorelibs/include` collides with Darling's real Darwin SDK
(`os/workgroup_object.h`: `unexpected type name 'OS_object'`). Removing it takes that build from 21
errors to 0.

### The Foundation half is an exposure problem, not an implementation problem

Darling's Foundation implements these classes; the Swift-facing names are what is missing. Measured
by compiling each name against Darling's SDK for the Darwin triple, ObjC spelling versus Swift
spelling:

| Swift name | resolves | ObjC name | resolves |
|---|---|---|---|
| `Bundle` | no | `NSBundle` | **yes** |
| `RunLoop` | no | `NSRunLoop` | **yes** |
| `UserDefaults` | no | `NSUserDefaults` | **yes** |
| `Thread` | no | `NSThread` | **yes** |
| `Scanner` | no | `NSScanner` | **yes** |
| `URLSession` | no | `NSURLSession` | **yes** |
| `NumberFormatter` | no | `NSNumberFormatter` | **yes** |
| `JSONSerialization` | no | `NSJSONSerialization` | **yes** |
| `MeasurementFormatter` | no | `NSMeasurementFormatter` | **yes** |
| `NotificationCenter` | no | `NSNotificationCenter` | **yes** |

Ten for ten. Across all 45 Foundation and formatter names from the remaining set:

| Count | Category |
|---|---|
| **21** | pure renames -- the ObjC class is present, only the Swift name is absent |
| **11** | Swift-only value types with no ObjC class behind them (`AttributedString`, the `FormatStyle` family, `ObservationTracking`) -- these need real implementations |
| **8** | ObjC class genuinely absent: 4 AppKit (`NSAnimationContext`, `NSSwitch`, `NSHapticFeedbackManager`, `NSDirectionalEdgeInsets`) and 4 Foundation formatters (`NSDateIntervalFormatter`, `NSEnergyFormatter`, `NSLengthFormatter`, `NSMassFormatter`) |
| **5** | `NSCoder`, `NSNumber`, `NSHashTable`, `NSMutableAttributedString`, `NSUserActivity` -- resolve standalone under `import Foundation` **and** under `import AppKit`, yet the full build reports `cannot find type`. **Not reproduced, not explained.** A two-file probe produces an access-level error, not this one. Do not assume it is the same cause as the 21. |

The curated SDK's `Foundation.apinotes` is 20 lines: `SwiftBridge` for NSString, NSArray,
NSDictionary and NSSet, plus two typedefs. It names none of the 21.

**No apinotes entries have been written.** This is the measurement, not the fix.

## Closed permanently: the corelibs Foundation route

Do not reopen this. The idea is that `BUILD_FOR_DARWIN_PLATFORM=0` routes the package down the Linux
path, where the CG geometry types and the Foundation classes come from swift-corelibs-foundation.
That works on Linux and **cannot** work here:

    could not find module 'Swift' for target 'arm64-apple-macos';
    found: aarch64-unknown-linux-gnu

The toolchain's only non-Darwin stdlib and Foundation are built for `aarch64-unknown-linux-gnu`.
Swift modules are target-tagged, and a Darwin triple is refused. Compiled on its own triple, corelibs
Foundation does supply `CGSize`, `CGRect`, `CGPoint`, `Bundle`, `RunLoop`, `Thread`, `UserDefaults`
and `AttributedString` -- verified, and irrelevant here.

## Proposal: fill out Darling's Foundation and CoreGraphics Swift overlays

Worth stating as its own project rather than as a SwiftUI blocker, because it is not one. Nothing in
it is specific to SwiftUI, and it unblocks every Swift application under Darling, not one framework.

**What exists** (`swift-darling/overlays`, built by `overlays/build.sh`, arm64, library evolution):
Darwin, ObjectiveC, CoreFoundation, Dispatch, os, XPC, CoreGraphics, AppKit, and a Foundation that
is deliberately limited to String/Array/Dictionary/Set bridging.

**What is missing**, as measured by one real consumer rather than guessed:

- **CoreGraphics: 12 types**, the value types first -- `CGSize`, `CGPoint`, `CGRect`,
  `CGAffineTransform`, then `CGColor`, `CGColorSpace`, `CGImage`, `CGDataConsumer`, `CGLineCap`,
  `CGLineJoin`.
- **Foundation: 27 types**, split between the Swift value layer (`AttributedString`,
  `AttributeContainer`, `AttributeScopes`, `FormatStyle`, `DiscreteFormatStyle`, `Data`, `URL`,
  `Bundle`, `RunLoop`, `Timer`, `Notification`, `UserDefaults`, `Thread`, `ProcessInfo`,
  `FileManager`, `DateFormatter`) and ObjC bridging (`NSAttributedString`,
  `NSMutableAttributedString`, `NSCoder`, `NSNumber`, `NSHashTable`).
- A tail of CoreText and CoreAnimation functions (`CTFontDescriptor*`, `CTLine`, `CATransform3D*`).

**Where to start.** The CoreGraphics value types are the highest leverage and the least risky: they
are small, their layout is fixed by the C structs already in the SDK, and they account for the
largest single share of the failures. Foundation's value layer is larger and needs real
implementations, not declarations, for the same reason the 114 must not be stubbed.

**The sequencing lesson from this run**: the six header gaps below were each found by fixing the
previous one and re-running. Expect the same here, and re-census the whole set after each change
rather than the piece just touched.

## Not measured yet

The symbol diff. Nothing here says how many of the 487 symbols AppZapper binds at the SwiftUI ordinal
this build actually exports. A clean compile is not coverage: the CryptoKit probe produced correct type
names, a clean compile and a clean link, and dyld still would not bind. Do not quote a coverage number
before `llvm-nm --defined-only` on the object has been diffed against the demanded list.

## Licence

Upstream is MIT (`LICENSE`), retained unchanged.
