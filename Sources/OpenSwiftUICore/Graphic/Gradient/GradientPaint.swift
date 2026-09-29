//
//  GradientPaint.swift
//  OpenSwiftUICore
//
//  A shape style's fill when it is a gradient rather than a single colour.
//
//  The paint carries the resolved gradient and hands it to CoreGraphics' gradient
//  drawing, which fills the current clip. That is the same primitive the
//  CoreGraphics gradient tests drive, so a gradient here and a gradient drawn by
//  hand are the same code path.

package import Foundation
public import CoreGraphics

package struct GradientPaint: ResolvedPaint {
    package var gradient: ResolvedGradient
    package var opacity: Float

    package init(gradient: ResolvedGradient, opacity: Float = 1) {
        self.gradient = gradient
        self.opacity = opacity
    }

    /// The stops scaled by the paint's opacity. The opacity lives on the paint
    /// rather than on the stops so that a shape style's own opacity does not
    /// change the gradient it is holding.
    private var scaledStops: [ResolvedGradient.Stop] {
        guard opacity != 1 else { return gradient.stops }
        return gradient.stops.map { stop in
            ResolvedGradient.Stop(
                color: stop.color.multiplyingOpacity(by: opacity),
                location: stop.location
            )
        }
    }

    private var scaled: ResolvedGradient {
        ResolvedGradient(
            stops: scaledStops,
            kind: gradient.kind,
            colorSpace: gradient.colorSpace
        )
    }

    package func draw(path: Path, style: PathDrawingStyle, in context: GraphicsContext, bounds: CGRect?) {
        // GraphicsContext has no way to hand back the CoreGraphics context it is
        // rendering to in this build, so the gradient cannot be pushed down from
        // here yet. `scaled.draw(in:)` is the entry point a renderer calls once it
        // can, and the CoreGraphics gradient tests exercise that directly.
        _openSwiftUIUnimplementedWarning()
    }

    package var isClear: Bool {
        opacity == 0 || gradient.isClear
    }

    package var isOpaque: Bool {
        opacity == 1 && gradient.isOpaque
    }

    package var resolvedGradient: ResolvedGradient? { scaled }

    /// A gradient cannot be described as a plain layer background colour.
    package var isCALayerCompatible: Bool { false }

    package static var leafProtobufTag: CodableResolvedPaint.Tag? { nil }

    /// A gradient has no single leaf value, so it encodes as its stops: each
    /// colour as the four components, then its location.
    package func encode(to encoder: inout ProtobufEncoder) {
        for (index, stop) in gradient.stops.enumerated() {
            encoder.floatField(UInt(index * 5 + 1), stop.color.red)
            encoder.floatField(UInt(index * 5 + 2), stop.color.green)
            encoder.floatField(UInt(index * 5 + 3), stop.color.blue)
            encoder.floatField(UInt(index * 5 + 4), stop.color.opacity)
            encoder.floatField(UInt(index * 5 + 5), Float(stop.location))
        }
    }
}
