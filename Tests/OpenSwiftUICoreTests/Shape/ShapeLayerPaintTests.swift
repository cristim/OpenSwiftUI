//
//  ShapeLayerPaintTests.swift
//  OpenSwiftUICoreTests
//
//  A shape layer can only be filled with a single colour. A paint it cannot
//  express used to clear the layer and log a warning, which left the shape
//  unpainted with nothing on screen to explain it. These tests pin the refusal so
//  the silent case cannot come back.
//

import Testing

#if canImport(Darwin)
import CoreGraphics
import QuartzCore
#endif

@testable import OpenSwiftUICore

@Suite("Shape layer paints")
struct ShapeLayerPaintTests {
    #if !os(iOS) && !os(visionOS)

    private static let rect = CGRect(x: 0, y: 0, width: 8, height: 8)

    private static func solidGradient() -> ResolvedGradient {
        ResolvedGradient(
            kind: .linear,
            startPoint: UnitPoint(x: 0, y: 0.5),
            endPoint: UnitPoint(x: 1, y: 0.5),
            startRadius: 0,
            endRadius: 1,
            colorSpace: .device,
            stops: [
                .init(
                    color: Color.Resolved(linearRed: 1, linearGreen: 0, linearBlue: 0, opacity: 1),
                    location: 0
                ),
                .init(
                    color: Color.Resolved(linearRed: 0, linearGreen: 0, linearBlue: 1, opacity: 1),
                    location: 1
                ),
            ]
        )
    }

    /// A gradient is drawn by the display list's Core Graphics renderer, not by a
    /// layer. Asking a layer for one must stop rather than quietly clear the fill.
    @Test
    func gradientPaintStopsInsteadOfSilentlyClearingTheLayer() async {
        await #expect(processExitsWith: .failure) {
            ShapeLayerHelper.requireLayerFill(for: GradientPaint(Self.solidGradient()))
        }
    }

    /// The other direction matters just as much: a paint the layer can express
    /// must keep working, or this is not a refusal but an outage.
    @Test
    func solidColorPaintIsAccepted() async {
        await #expect(processExitsWith: .success) {
            let color = ShapeLayerHelper.requireLayerFill(
                for: Color.Resolved(linearRed: 1, linearGreen: 0, linearBlue: 0, opacity: 1)
            )
            #expect(color.red == 1)
        }
    }

    #endif
}
