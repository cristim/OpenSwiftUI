//
//  GraphicsImageHeadroomTests.swift
//  OpenSwiftUICoreTests

#if canImport(Darwin) && OPENSWIFTUI_NO_CG_HEADROOM_SPI
import CoreGraphics
@_spi(Private)
@testable
import OpenSwiftUICore
import Testing

struct GraphicsImageHeadroomTests {
    @Test
    func pqImageFallsBackWithoutHeadroomSPI() throws {
        let space = try #require(CGColorSpace(name: CGColorSpace.itur_2100_PQ))
        let context = try #require(CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 16, bytesPerRow: 0,
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
        #expect(image.headroom == .high)
    }
}
#endif
