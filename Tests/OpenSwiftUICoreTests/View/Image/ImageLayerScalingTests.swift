//
//  ImageLayerScalingTests.swift
//  OpenSwiftUICoreTests

#if canImport(Darwin) && OPENSWIFTUI_NO_CACONTENTSSCALING && !OPENSWIFTUI_DEVELOPMENT
import CoreGraphics
import QuartzCore
@_spi(Private)
@testable
import OpenSwiftUICore
import Testing

struct ImageLayerScalingTests {
    @Test
    func untiledImageUpdatesWithoutScalingProperty() throws {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let cgImage = try #require(context.makeImage())
        let image = GraphicsImage(
            contents: .cgImage(cgImage),
            scale: 1,
            unrotatedPixelSize: CGSize(width: 1, height: 1),
            orientation: .up,
            isTemplate: false
        )
        let layer = ImageLayer()
        layer.update(image: image, size: CGSize(width: 1, height: 1))
        #expect(layer.contentsCenter == CGRect(x: 0, y: 0, width: 1, height: 1))
    }
}
#endif
