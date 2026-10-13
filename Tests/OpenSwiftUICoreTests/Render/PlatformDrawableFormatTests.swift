//
//  PlatformDrawableFormatTests.swift
//  OpenSwiftUICoreTests

#if canImport(Darwin) && OPENSWIFTUI_NO_CA_A8_FORMAT
import QuartzCore
@_spi(DisplayList_ViewSystem)
@testable
import OpenSwiftUICore
import Testing

struct PlatformDrawableFormatTests {
    @Test
    func alphaOnlyUsesRGBA8WithoutA8Format() {
        let options = PlatformDrawableOptions(base: RasterizationOptions(flags: [.alphaOnly]))
        #expect(options.caLayerContentsFormat == .RGBA8Uint)
    }
}
#endif
