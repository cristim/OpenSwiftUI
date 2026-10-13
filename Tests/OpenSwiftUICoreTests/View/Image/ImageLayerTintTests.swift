//
//  ImageLayerTintTests.swift
//  OpenSwiftUICoreTests

#if canImport(Darwin) && OPENSWIFTUI_NO_CACONTENTSSWIZZLE
import CoreGraphics
import QuartzCore
@_spi(Private)
@testable
import OpenSwiftUICore
import Testing

struct ImageLayerTintTests {
    @Test
    func templateImageIsTintedOnTheCPU() throws {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        let source = try #require(CGContext(
            data: nil, width: 2, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: info
        ))
        // Left pixel opaque black, right pixel fully transparent.
        source.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        source.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        let cgImage = try #require(source.makeImage())
        var image = GraphicsImage(
            contents: .cgImage(cgImage),
            scale: 1,
            unrotatedPixelSize: CGSize(width: 2, height: 1),
            orientation: .up,
            isTemplate: false
        )
        image.maskColor = Color.red.resolve(in: EnvironmentValues())
        let layer = ImageLayer()
        layer.update(image: image, size: CGSize(width: 2, height: 1))

        let tinted = try #require(layer.contents as! CGImage?)
        let readback = try #require(CGContext(
            data: nil, width: 2, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: info
        ))
        readback.draw(tinted, in: CGRect(x: 0, y: 0, width: 2, height: 1))
        let pixels = try #require(readback.data).assumingMemoryBound(to: UInt8.self)
        #expect(pixels[0] == 255 && pixels[1] == 0 && pixels[2] == 0 && pixels[3] == 255)
        #expect(pixels[7] == 0)
    }
}
#endif
