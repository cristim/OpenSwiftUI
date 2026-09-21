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

### Retirement trigger for the Foundation and CommonCrypto generators

`make-foundation-module.sh` and `make-commoncrypto-module.sh` exist here because **the fork is
currently strictly better than Darling's SDK by exactly three names**. Delete them, and stop
generating an overlay Foundation, when ALL THREE of these hold:

1. **VibeDarling/darling#113 merged** -- the same two fixes in their real home: the SDK's Foundation
   module map and CommonCrypto in the generated `usr/include` map. Measured in its own configuration
   it is net **+6**, not +9.
2. **`darling-foundation`'s `Foundation.apinotes` carries `SwiftName` for `NSBundle`,
   `NSDateFormatter` and `NSNotificationCenter`.** Those three are why #113 is +6 rather than +9:
   once Darling's own `Foundation.framework` wins the search path, the apinotes that applies is the
   one in pinned `src/external/foundation`, which lacks them. This fork's curated SDK carries them
   locally. They were deliberately held out of darling-foundation#37 because they break 11 call
   sites in darling-swift, so landing them is a coordinated pair: the three `SwiftName` entries plus
   the 11 call-site fixes, together.
3. **Darling's `foundation` submodule pin includes both.**

Until then the SDK route regresses `Bundle`, `DateFormatter` and `NotificationCenter`. Running both
mechanisms at once is the failure mode to avoid; this file is the record of which one is live.

### RETRACTED: "Foundation must go in the overlay as headers only"

**This file previously stated, as a predictive rule, that giving Foundation a module map breaks
AppKit with `cannot find interface declaration for 'NSLayoutConstraint'`. That rule is WITHDRAWN.
It is false, and acting on it cost nine names.**

Left as a retraction rather than deleted, so a reader who half-remembers it knows it was withdrawn
rather than wondering whether they misread.

The rule that replaces it:

> **Every framework in the overlay gets a module map, Foundation included.**
> `Darling/make-framework-modules.sh` writes one per framework with an umbrella *header*;
> `Darling/make-foundation-module.sh` writes Foundation's, which needs a *directory* umbrella.

Why the old evidence was real but misread: `Foundation.h` reaches only 152 of the 202 headers. With
`umbrella header "Foundation.h"` the other 50 -- `NSLayoutConstraint.h` and `NSNumber.h` among them
-- sit in the framework but in no module, so importing them imports a Foundation that does not
declare them. A directory umbrella covers all 202 and the diagnostic goes away. Two headers must
stay excluded, both unreachable from `Foundation.h`, so neither bug is new:

    NSMutableCharacterSet.h:1  #import <Foundation/NSCharactrSet.h>   (misspelt, no such file)
    NSSerializer.h:4           duplicate interface definition for class 'NSDeserializer'

**CoreGraphics**: an earlier note here said it must stay headers-only because a module map produced
`cyclic dependency in module 'CoreGraphics': CoreGraphics -> Foundation -> CoreGraphics`. That cycle
was genuine and is now **fixed upstream** by darling-cocotron#124, which split the private
window-server headers out of the public umbrella. With #124 applied, CoreGraphics modularises
cleanly and all four acceptance checks pass. Without it, the cycle returns.

**The lesson, and the reason this is a retraction rather than an edit.** The observation was
accurate -- that configuration really did fail that way. The error was the *scope* of the claim.
"I could not make a modular Foundation work" became "modular Foundation does not work", and writing
it into a handover gave it authority it never earned. State the configuration with the finding, and
prefer "I could not make X work this way" to "X does not work". The first invites a second attempt;
the second forecloses one. That matters most when a failure is expensive to reproduce, because that
is exactly when people take your word instead of re-running it.

With the rule followed, all nine Clang modules the build needs import cleanly: AppKit, CoreText,
QuartzCore, COpenSwiftUI, OpenSwiftUI_SPI, UIFoundation_Private, CoreText_Private,
CoreGraphics_Private and QuartzCore_Private.

`Darling/probe-clang-modules.sh` re-runs this census in seconds. Re-run it over the **whole** set
after each change, never just the framework you touched: adding QuartzCore's module map broke AppKit,
which had been importing fine, by surfacing `CAOpenGLLayer`'s missing `#include <OpenGL/gl.h>`.

## The Foundation/AppKit module binding conflict

**Symptom.** One file, and two of the names go missing:

```swift
import AppKit
package import Foundation
package func q(_ x: URLSession) -> URLSession { x }   // cannot find type 'URLSession' in scope
package func k(_ x: NSCoder) -> NSCoder { x }         // ... uses an internal type
```

Drop `import AppKit` and both resolve. Two files, one importing AppKit and one importing
Foundation, reproduce it across files.

**What the module-loading trace says.** `-Rmodule-loading` plus `-Xcc -Rmodule-build -Xcc
-Rmodule-import` prints the whole graph; the decisive line is not in the trace but in the module
file itself:

    clang -cc1 -module-file-info <cache>/AppKit-*.pcm
      Imports module 'Darwin' ... 'CoreGraphics' ... 'CoreText' ... 'QuartzCore' ... 'OpenGL'

**AppKit does not import Foundation at all.** Its `#import <Foundation/Foundation.h>` finds a
Foundation.framework with no `Modules/` directory, so Clang inlines the whole header set
*textually* into module AppKit. The Foundation pcm built afterwards for Swift's own `import
Foundation` is byte-identical with and without `import AppKit` (same content hash), so the header
set was never the variable. What changes is **which module owns the declarations**.

Two Swift behaviours are keyed on that owning module, and both switch off when it is AppKit:

- **API notes are per-module.** `Foundation.apinotes` carries the `SwiftName` entries that make
  `NSURLSession` import as `URLSession`, `NSScanner` as `Scanner`. Clang consults
  `AppKit.apinotes` for decls in module AppKit, and there is none, so only the `NS`-prefixed
  spellings exist. Confirmed both ways: with AppKit imported `NSURLSession` and `NSScanner`
  compile; without it they compile too, and are rejected as *renamed* to the Swift spellings.
  (This is also why copying `Foundation.apinotes` next to the overlay's headers changed nothing.)
- **Import access level follows the import that exposes the decl.** Under
  `InternalImportsByDefault`, `import AppKit` is an internal import. A decl owned by module AppKit
  is therefore internal even in a file that says `package import Foundation`, which is the
  `function cannot be declared package because its parameter uses an internal type` on `NSCoder`,
  `NSNumber`, `NSMutableAttributedString`, `NSUserActivity` and `NSMapTable`.

**The fix** is `Darling/make-foundation-module.sh`: put a *modular* Foundation in the overlay,
built from the curated SDK's headers (the copy that carries `Foundation.apinotes`), with a
directory umbrella so all 202 headers are in the module, and two headers excluded because they
cannot compile at all. AppKit's pcm then lists `Imports module 'Foundation'` and the decls stay
Foundation's.

Measured on the full 881-file build, sorted file order (the name set moves if the order changes,
so state it), against the same tree with only the overlay's Foundation swapped and the two module
maps below added -- **9 distinct names clear and none regress**, 2327 error lines to 2255:

| Cleared | By |
|---|---|
| `NSAttributedString`, `NSCoder`, `NSMutableAttributedString`, `NSNumber`, `NSUserActivity`, `Scanner`, `URLSession`, `resourceValues` | the modular Foundation |
| `CC_SHA1_Update` | the CommonCrypto module map, below |

`NSHashTable` and `NSAttributedString.Key` are **not** part of this. They fail identically with and
without `import AppKit`, and they are plain SDK gaps: Darling's `NSHashTable.h` declares
`@interface NSHashTable : NSObject` with no lightweight generics, and nothing maps
`NSAttributedStringKey` to the nested `NSAttributedString.Key`. `NSUserActivityDelegate` is not
declared anywhere in Darling's Foundation headers.

### It also removes most of the file-order sensitivity

The single-frontend compile's missing-name set moves when the file order changes, which is why
every count here states its order. Measured over all four combinations of {baseline, this fix} x
{sorted, reverse-sorted} on the same 881 files:

| | names | order-sensitive names |
|---|---|---|
| baseline, sorted | 95 | `IOSurfaceRef`, `NSMutableAttributedString`, `NSUserActivity` only here |
| baseline, reversed | 96 | `NSCalendar`, `NSKeyedUnarchiver`, `NotificationCenter`, `ProcessInfo` only here |
| fixed, sorted | 86 | `IOSurfaceRef` only here |
| fixed, reversed | 85 | -- |

Seven names moved with the order before; one does after, and that one (`IOSurfaceRef`) moved
before as well, so nothing new is order-dependent. The fix clears 9 names in sorted order and 11
in reversed order; the union of 13 is the set it makes order-independent.

Why an umbrella gap would produce order sensitivity at all: four of those seven
(`NSKeyedUnarchiver`, `NSNotificationCenter`, `NSMutableAttributedString`, `NSNumber`) are among
the 50 headers `Foundation.h` does not reach, so whether their decls were visible depended on
which file's imports had already dragged them in textually. `NSCalendar` and `NSProcessInfo` are
reachable from the umbrella, so for those two it is the module-ownership half of the bug, not the
umbrella half. Both halves are fixed by the same change.

`NotificationCenter` never appears as a missing *type* in sorted order, which is why it is absent
from the 75-name list and from the cleared set. What remains for it in both orders is a different
and real gap: `NSHostingView.swift:413` reports `type 'NotificationCenter' has no member
'default'`, the same shape as `URLSession.shared`.

### Two Foundation headers that have never compiled

Both are excluded from the module map, which leaves them textual, exactly where they were before.
Neither bug is new: both headers are unreachable from the `Foundation.h` umbrella, so nothing had
ever preprocessed them. They belong in darling-foundation, not here.

| Header | Defect |
|---|---|
| `NSMutableCharacterSet.h:1` | `#import <Foundation/NSCharactrSet.h>` -- misspelt, no such file |
| `NSSerializer.h:4` | `duplicate interface definition for class 'NSDeserializer'` |

## Two more modules: CommonCrypto and IOSurface

Both are "present but unnamed": the declarations are in the SDK, nothing declares a module over
them, so `canImport` is false and the names do not resolve. Neither needs new API.

- **CommonCrypto** (`CC_SHA1_Update`, declared at `usr/include/CommonCrypto/CommonDigest.h:161`).
  It is in `usr/include`, so it cannot be a framework module; and all 25 of its headers are
  `exclude header`-ed from the SDK's Darwin module, so it cannot be a Darwin submodule either.
  `Darling/make-commoncrypto-module.sh` writes a standalone top-level module map over
  `CommonCrypto/CommonCrypto.h`, passed with `-Xcc -fmodule-map-file=`. `StrongHash.swift` already
  guards its use with `#if canImport(CommonCrypto)` and imports it, so no source change is needed:
  `CC_SHA1_Update` clears in the full build.
- **IOSurface** has an umbrella header, so `Darling/make-framework-modules.sh IOSurface` is enough
  and the module builds. `IOSurfaceRef` does **not** clear, for two reasons that are outside the
  module map: `GraphicsImage.swift:24` spells the type with no `import IOSurface`, and Darling's
  `IOSurfaceRef.h` declares it as a CF-style opaque pointer (`typedef struct __IOSurface *`), so
  Swift strips the `Ref` and the type is spelled `IOSurface` (`'IOSurfaceRef' has been renamed to
  'IOSurface'`). Apple's SDK avoids that by backing the typedef with the `IOSurface` ObjC class;
  Darling declares that class in `IOSurfaceObjC.h`, which its own umbrella does not include.

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

**IOSurface** was added later and needs nothing special: it has an umbrella header.

Two cannot be done this way: **CoreUI** and **Accessibility** have no headers in Darling at all.
**CommonCrypto** also lives in `usr/include` rather than a framework, and has its own script:
`Darling/make-commoncrypto-module.sh`.

**Neither of the two is actually required**, so the module-map route does not terminate here:

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
  own frameworks, so `#import <Foundation/Foundation.h>` from AppKit resolves to the overlay's
  Foundation, not the curated one in the sysroot. That is why the overlay's Foundation has to be
  the modular one: see "The Foundation/AppKit module binding conflict" below. The two header sets
  are the same files; the curated SDK adds only `Foundation.apinotes`.

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

### The NSTextAttachment ODR clash, applied as a build-time patch

`NSTextAttachment`, `NSTextTab`, `NSParagraphStyle` and `NSMutableParagraphStyle` are declared both
by `Shims/UIFoundation` and by Darling's AppKit, and clang compares the **whole interface**, not the
name, so the two definitions clash:

    NSTextTab.h:35:13: error: 'NSTextTab::_location' from module 'AppKit.NSTextTab'
      is not present in definition of 'NSTextTab' in module 'UIFoundation_Private'

Not a cocotron regression: the three AppKit headers are byte-identical between the stale snapshot
and master, with 30 other AppKit headers differing as a control. And moving cocotron's 18 public
ivars is necessary but **not sufficient**, because a property-versus-getter shape difference still
clashes, so cocotron can never match Apple's headers byte for byte. The fix therefore belongs here.

**It lives in `Darling/patches/`, not in `Sources/`.** `Darling/stage-spi.sh <staging dir>` copies
`Sources/OpenSwiftUI_SPI` and applies every patch in `Darling/patches/` to the copy; the build then
points at the staged copy instead of at `Sources/`:

    Darling/stage-spi.sh "$STAGE"
    -Xcc -I$STAGE/Sources/OpenSwiftUI_SPI
    -Xcc -fmodule-map-file=$STAGE/Sources/OpenSwiftUI_SPI/module.modulemap

Same reason `stage-as-swiftui.py` rewrites imports into a staging tree rather than editing files in
place: a new upstream release stays a `git rebase` instead of a conflict, and the Darling-only
header changes stay legible as one diff rather than dissolving into the vendored headers. The cost
is that the headers the compiler sees are no longer the headers in the tree, so a build that forgets
the `-I` silently gets the unpatched ones - which is what the clash diagnostic above looks like.

The script applies with `-F0` (no fuzz) and removes the staged copy if any hunk fails, so a patch
whose context has drifted stops the build instead of half-applying. Verified by drifting one context
line in a throwaway copy: exit 1, and no staged tree left behind.

What the patch does, per header:

- Each redeclaration is wrapped in `#if !__has_include(<AppKit/...>)`, with an `#import` of AppKit's
  header in the other arm, because the `(OpenSwiftUI_SPI)` categories need the class to exist.
- **`NSMutableParagraphStyle` gets no import of its own.** Apple's AppKit has no
  `<AppKit/NSMutableParagraphStyle.h>`; the class is declared inside `NSParagraphStyle.h`. Importing
  it under `__has_include(<AppKit/NSParagraphStyle.h>)` would be a file-not-found on a real SDK,
  which is precisely the platform this guard is being trusted on. On Darling it is redundant anyway:
  cocotron's `AppKit/NSParagraphStyle.h` imports `NSMutableParagraphStyle.h` itself.
- **The import has to sit outside `NS_HEADER_AUDIT_BEGIN.`** Inside one, clang refuses it with
  `cannot #include files inside '#pragma clang assume_nonnull'`, and the unbalanced pragma then
  produces a second, unrelated-looking error at the end of the file.
- **`NSLineBreakMode` is guarded too.** AppKit declares it as well, and once AppKit's header is in
  this module two visible declarations are `reference to 'NSLineBreakMode' is ambiguous` - an
  ambiguity, not a clash, and a different diagnostic. `NSLineBreakStrategy` beside it is **not**
  guarded: AppKit does not declare it.

Measured with a two-module Swift probe (`import AppKit` + `import UIFoundation_Private`, then a
function mentioning each of the four types, which is what forces clang to compare the definitions -
importing both modules and stopping there does **not** reproduce it):

| | exit | errors |
|---|---|---|
| `Sources/` as it stands | 1 | 4, all ODR |
| staged copy, patch applied | 0 | 0 |

Controls both ways in the same runs: the same file without `import AppKit` compiles in both, and a
fabricated type name fails in both. The single-module census (`UIFoundation_Private`,
`OpenSwiftUI_SPI`) is `OK` against the staged copy, with a nonexistent module name failing beside it.

**Residue, to report rather than chase.** Taking AppKit's smaller classes leaves 8 ordinary
missing members, all header-and-implementation work in cocotron's AppKit, not here:

| type | members |
|---|---|
| `NSTextAttachment` | `bounds`, `contents`, `fileType`, `image`, `lineLayoutPadding` |
| `NSMutableParagraphStyle` | `allowsDefaultTighteningForTruncation`, `lineBreakStrategy`, `usesDefaultHyphenation` |

`NSTextTab.location` and `.options` resolve, as do the other paragraph-style members used here.

**One caveat, stated because the section below draws exactly this distinction.** Unlike `CAFilter`,
where `<QuartzCore/CAFilter.h>` exists only on Darling, **Apple's AppKit ships all three of these
headers too**, so the predicate is true on macOS as well. Being a patch rather than a source edit
takes most of the sting out of that: nothing changes for anyone who does not run `stage-spi.sh`.
It still was not checked against a real SDK, which by the rule below is the `CADisplayLink`
situation rather than the `CAFilter` one.

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

## READ FIRST: every name count in this file undercounts by roughly 3.6x

The counts (103, 97, 83, 75) were extracted from `cannot find type 'X'` and `cannot find 'X' in
scope` diagnostics only. **That extraction cannot see `type 'X' has no member 'Y'`.** Missing
*members of present types* were invisible to it, in every framework, at every step.

Measured on the same build that produced 75:

| | distinct | call sites |
|---|---|---|
| names the count captured | 75 | -- |
| **missing members it never saw** | **196** | **1,186** |
| spread over | 66 distinct types | |

So the real remaining surface is about **271 items, not 75**.

**Read 271 as a first measurement, not as a revision of 75.** The member count has never been taken
before, at any point in this work. The type trajectory 103 -> 97 -> 83 -> 75 is valid as a
like-for-like comparison, because the same extraction ran at each step -- but it is a trajectory for
*types only*. There is no member trajectory, so there is no evidence that the member count is
falling, rising or flat. Treating 271 as "75 corrected upward" would imply a trend nobody has data
for. The next person to measure it establishes the second point, not the second revision.

Two different defects are recorded in this file and they have different fixes. This one is an
**extraction bug**: one missing regex, fixed once, and then correct forever. The instrument faults
listed elsewhere are a different class -- each was caught by a control that could fail, never by
inspection -- and no single fix retires them.

This is also the root of the cascade error recorded below: `CGRect.minX` appears only as
`type 'CGRect' has no member 'minX'`, never as a missing name, so it read as a downstream effect of
the missing `CGRect` type rather than as its own item.

**Any future count must extract both diagnostic forms.** A member of a present type is its own
category, and it is the larger one.

### After darling-swift#42

#42 ships 24 of the 196 (546 of 1,186 sites): all 19 CGRect members, `CGPoint.zero`, both CGSize
members, and `CGImage.width`/`height`. Verified by that PR's author at symbol level, by demangling
the gained symbols rather than reading source.

**Remaining: 172 distinct members over 640 sites.** Largest owners:

| members | sites | type |
|---|---|---|
| 28 | 58 | `CGBlendMode` |
| 11 | 60 | `CALayer` |
| 10 | 40 | `String?` |
| 9 | 36 | `NSWindow` |
| 6 | 12 | `PlatformSwitch` |
| 5 | 82 | `CGAffineTransform` |
| 5 | 18 | `NSEvent` |
| 5 | 14 | `CGColorSpace` |
| 5 | 14 | `CGColor` |
| 4 | 18 | `Locale` |
| 4 | 10 | `CGContext` |

### The remaining CoreGraphics demand is three mechanisms, not one job

Recorded here because `VibeDarling/darling-swift` has issues disabled, so #42's body is the only
other record and it disappears from view when that PR merges.

- **C enums** -- `CGBlendMode` (28 cases), `CGLineCap`, `CGLineJoin`, `CGImageAlphaInfo.alphaOnly`.
  If Darling's headers declare the cases these import for free: a header fix, not Swift.
- **Renames of C globals** -- `CGColorSpace.sRGB`, `.displayP3`, `.extendedSRGB`, `.linearSRGB`,
  `.extendedLinearSRGB`.
- **api-notes renames of C functions Darling already exports** -- `CGAffineTransform.inverted`,
  `.concatenating`, `.translatedBy` (from `CGAffineTransformInvert/Concat/Translate`), and
  `CGContext.scaleBy`, `.translateBy` (from `CGContextScaleCTM/TranslateCTM`).
- Genuinely absent and still to place: `CGImage.colorSpace`, `CGAffineTransform.identity` (which
  drags in its four siblings), `CGDrawingLayer.contentsScale`, `CGColor` (5), `CGPath`/`CGMutablePath`.

`CGVector` appears nowhere in the demand; do not add it.

### CALayer's members are NOT overlay work -- none of the 11

Corrected by measurement, not inherited, and established for the whole set rather than a sample.

The decisive evidence: the real Apple 5.2.2 `libswiftQuartzCore` x86_64 slice committed in
darling-swift exports **six symbols, all of them CATransform3D-to-NSValue bridging, and zero CALayer
members**. There is no Swift overlay surface on CALayer on macOS at all. Every CALayer member reaches
Swift as an imported Objective-C property or method, or as an api-notes rename of one. So all 11
missing members are either absent from Darling's `@interface` or present under a different Swift
name, and both are header-and-implementation work in cocotron's QuartzCore.

Per-member detail for the five probed directly: `allowsEdgeAntialiasing`, `contentsCenter`,
`contentsFormat` and `contentsScale` are absent from the `@interface` entirely -- no backing storage,
and `contentsScale` must be honoured by CARenderer. `isOpaque` fails for a different reason: the
header declares `@property BOOL opaque;` with no `getter=isOpaque`.

The discriminating evidence, in one run: `hidden` FAILS and `isHidden` PASSES, because only the
latter is declared `@property(getter=isHidden)`; `cornerRadius` passes and a fabricated member fails,
so the probe can go both ways. These belong in cocotron's QuartzCore header and implementation.

## Handover: the wall at 75, and the cascade correction that makes it bigger

**The count is 75 distinct missing names, and it is conditioned on an unmerged PR.** It was measured
with darling-cocotron **#124 at `239faa6c`**, which is open and not an ancestor of cocotron master
(`9d1c81ac`). Against master the Foundation to CoreGraphics to Foundation cycle returns and the
AppKit Clang module fails with `redefinition of 'NSRectEdge'`. Both states were reproduced, so this
is a dependency with a commit in it, not a caveat. Re-derive the number if #124 changes or lands.

Trajectory: 103 -> 97 -> 83 -> 75 -> **66**, the last step being the nine names above.
The SDK header corpus was byte-identical to its source across
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

### The six unexplained: solved

`NSCoder`, `NSNumber`, `NSMutableAttributedString`, `NSUserActivity`, `Scanner` and `URLSession`
were all the same defect: module AppKit owned them, because a headers-only Foundation is absorbed
textually. See "The Foundation/AppKit module binding conflict" above; all six clear with a modular
Foundation in the overlay. The four mechanisms below were proposed and disproved on the way, and
are kept so nobody re-runs them:

1. **Missing from Foundation.** No: each resolves under a plain `import Foundation`.
2. **Framework re-export.** Files importing only AppKit or QuartzCore do lose Swift Foundation, and
   that explained ten *other* names -- but these six resolve under `import AppKit` alone too.
3. **Value versus type position.** No: `Scanner(string:)` resolves in value position. (`URLSession.shared`
   fails differently, because Darling declares it as a method -- a separate real bug.)
4. **The file's own import set.** No: rebuilding `Foundation` + `OpenSwiftUI_SPI` +
   `UIFoundation_Private` still resolves `Scanner`, with the control failing in the same run.

One unread clue, still unexplained and no longer worth chasing: `Scanner` and `URLSession` were
not failing before the CoreGraphics module landed and were after. The mechanism is now known
independently of it, so the correlation was never needed.

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
