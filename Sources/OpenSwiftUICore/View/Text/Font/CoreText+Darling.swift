//
//  CoreText+Darling.swift
//  OpenSwiftUICore
//
//  Replaces the private CoreText SPI in CoreText+Private.swift when the host CoreText
//  does not export it (OPENSWIFTUI_NO_CORETEXT_SPI, defined only by Darling/build-*.sh).
//
//  Every token below is a module-local opaque value. The spellings belong to OpenSwiftUI,
//  are never passed to system code and are not Apple's strings; they are only compared or
//  used as dictionary keys inside OpenSwiftUI.
//
//  Not covered here (need a user decision, see the text-style size table and Font.Width
//  questions): the descriptor factories, the system-font provenance predicates, the weight
//  getters and constants, and the kCTFontWidth* constants.

#if canImport(CoreText) && OPENSWIFTUI_NO_CORETEXT_SPI
import CoreText
import CoreFoundation
import Foundation

// MARK: - Functions

/// Absent capability: no character set, so `NSAttributedString.oversizedScalars` is empty.
package func CTFontCopySystemUIFontExcessiveLineHeightCharacterSet() -> CFCharacterSet? {
    _darlingCapabilityAbsent("oversizedScalars")
    return nil
}

/// Absent capability: nil makes `.contentAware` fall through to the locale language.
package func CTFontCopyTallestTextStyleLanguageForString(_ string: CFString) -> CFString? {
    _darlingCapabilityAbsent("tallestTextStyleLanguage")
    return nil
}

/// Absent capability: `false` means the font has no language-aware outsets.
package func CTFontGetLanguageAwareOutsets(
    _ font: CTFont,
    _ left: UnsafeMutablePointer<CGFloat>,
    _ top: UnsafeMutablePointer<CGFloat>,
    _ right: UnsafeMutablePointer<CGFloat>,
    _ bottom: UnsafeMutablePointer<CGFloat>
) -> Bool {
    _darlingCapabilityAbsent("languageAwareOutsets")
    return false
}

/// Absent capability: `false` means no clipping metrics are available for the font.
package func CTFontGetClippingMetrics(
    _ font: CTFont,
    _ ascent: UnsafeMutablePointer<CGFloat>,
    _ descent: UnsafeMutablePointer<CGFloat>
) -> Bool {
    _darlingCapabilityAbsent("clippingMetrics")
    return false
}

/// No mapping is known. The only caller runs when `legibilityWeight == .bold`, which the
/// Darling environment never produces, so reaching this is a bug to find, not to hide.
package func CTFontGetAccessibilityBoldWeightOfWeight(_ weight: CGFloat) -> CGFloat {
    fatalError("CTFontGetAccessibilityBoldWeightOfWeight has no Darling implementation")
}

// MARK: - Trait and attribute keys

let kCTFontUIFontDesignTrait: CFString = "OpenSwiftUI.CoreText.UIFontDesignTrait" as CFString

/// Absent capability: nil, and `GradeModifier` skips the descriptor change.
let kCTFontGradeTrait: CFString? = nil

let kCTFontLegibilityWeightAttribute: CFString = "OpenSwiftUI.CoreText.LegibilityWeightAttribute" as CFString

let kCTFontDescriptorLanguageAttribute: CFString = "OpenSwiftUI.CoreText.DescriptorLanguageAttribute" as CFString

let kCTFontLanguageAwareLineHeightRatioAttribute: CFString = "OpenSwiftUI.CoreText.LanguageAwareLineHeightRatioAttribute" as CFString

let kCTTextScaleRatioAttributeName: CFString = "OpenSwiftUI.CoreText.TextScaleRatioAttribute" as CFString

// MARK: - CTFontTextStyle

let kCTUIFontTextStyleTitle0: CFString = "OpenSwiftUI.CoreText.TextStyle.Title0" as CFString
let kCTUIFontTextStyleTitle1: CFString = "OpenSwiftUI.CoreText.TextStyle.Title1" as CFString
let kCTUIFontTextStyleTitle2: CFString = "OpenSwiftUI.CoreText.TextStyle.Title2" as CFString
let kCTUIFontTextStyleTitle3: CFString = "OpenSwiftUI.CoreText.TextStyle.Title3" as CFString
let kCTUIFontTextStyleHeadline: CFString = "OpenSwiftUI.CoreText.TextStyle.Headline" as CFString
let kCTUIFontTextStyleSubhead: CFString = "OpenSwiftUI.CoreText.TextStyle.Subhead" as CFString
let kCTUIFontTextStyleBody: CFString = "OpenSwiftUI.CoreText.TextStyle.Body" as CFString
let kCTUIFontTextStyleCallout: CFString = "OpenSwiftUI.CoreText.TextStyle.Callout" as CFString
let kCTUIFontTextStyleFootnote: CFString = "OpenSwiftUI.CoreText.TextStyle.Footnote" as CFString
let kCTUIFontTextStyleCaption1: CFString = "OpenSwiftUI.CoreText.TextStyle.Caption1" as CFString
let kCTUIFontTextStyleCaption2: CFString = "OpenSwiftUI.CoreText.TextStyle.Caption2" as CFString
let kCTUIFontTextStyleExtraLargeTitle: CFString = "OpenSwiftUI.CoreText.TextStyle.ExtraLargeTitle" as CFString
let kCTUIFontTextStyleExtraLargeTitle2: CFString = "OpenSwiftUI.CoreText.TextStyle.ExtraLargeTitle2" as CFString
let kCTUIFontTextStyleCaption3: CFString = "OpenSwiftUI.CoreText.TextStyle.Caption3" as CFString
let kCTUIFontTextStyleFootnote2: CFString = "OpenSwiftUI.CoreText.TextStyle.Footnote2" as CFString

// MARK: - CTFontDesign

let kCTFontUIFontDesignDefault: CFString = "OpenSwiftUI.CoreText.UIFontDesign.Default" as CFString
let kCTFontUIFontDesignSerif: CFString = "OpenSwiftUI.CoreText.UIFontDesign.Serif" as CFString
let kCTFontUIFontDesignRounded: CFString = "OpenSwiftUI.CoreText.UIFontDesign.Rounded" as CFString
let kCTFontUIFontDesignMonospaced: CFString = "OpenSwiftUI.CoreText.UIFontDesign.Monospaced" as CFString
let kCTFontUIFontDesignCompact: CFString = "OpenSwiftUI.CoreText.UIFontDesign.Compact" as CFString
let kCTFontUIFontDesignCompactRounded: CFString = "OpenSwiftUI.CoreText.UIFontDesign.CompactRounded" as CFString
let kCTFontUIFontDesignSoft: CFString = "OpenSwiftUI.CoreText.UIFontDesign.Soft" as CFString
let kCTFontUIFontDesignCompactSoft: CFString = "OpenSwiftUI.CoreText.UIFontDesign.CompactSoft" as CFString

// MARK: - CTFontContentSizeCategory

let kCTFontContentSizeCategoryXS: CFString = "OpenSwiftUI.CoreText.ContentSizeCategory.XS" as CFString
let kCTFontContentSizeCategoryS: CFString = "OpenSwiftUI.CoreText.ContentSizeCategory.S" as CFString
let kCTFontContentSizeCategoryM: CFString = "OpenSwiftUI.CoreText.ContentSizeCategory.M" as CFString
let kCTFontContentSizeCategoryL: CFString = "OpenSwiftUI.CoreText.ContentSizeCategory.L" as CFString
let kCTFontContentSizeCategoryXL: CFString = "OpenSwiftUI.CoreText.ContentSizeCategory.XL" as CFString
let kCTFontContentSizeCategoryXXL: CFString = "OpenSwiftUI.CoreText.ContentSizeCategory.XXL" as CFString
let kCTFontContentSizeCategoryXXXL: CFString = "OpenSwiftUI.CoreText.ContentSizeCategory.XXXL" as CFString
let kCTFontContentSizeCategoryAccessibilityM: CFString = "OpenSwiftUI.CoreText.ContentSizeCategory.AccessibilityM" as CFString
let kCTFontContentSizeCategoryAccessibilityL: CFString = "OpenSwiftUI.CoreText.ContentSizeCategory.AccessibilityL" as CFString
let kCTFontContentSizeCategoryAccessibilityXL: CFString = "OpenSwiftUI.CoreText.ContentSizeCategory.AccessibilityXL" as CFString
let kCTFontContentSizeCategoryAccessibilityXXL: CFString = "OpenSwiftUI.CoreText.ContentSizeCategory.AccessibilityXXL" as CFString
let kCTFontContentSizeCategoryAccessibilityXXXL: CFString = "OpenSwiftUI.CoreText.ContentSizeCategory.AccessibilityXXXL" as CFString

#endif
