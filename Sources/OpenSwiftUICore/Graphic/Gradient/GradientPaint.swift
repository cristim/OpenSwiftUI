//
//  GradientPaint.swift
//  OpenSwiftUICore
//
//  Paints a resolved gradient into a real Core Graphics context.
//

//  Status: Complete

#if canImport(Darwin)
public import CoreGraphics
#endif

/// A resolved gradient as something that can fill a path.
///
/// A gradient cannot be a `Color.Resolved`, which holds a single value, so routing
/// one through the solid-fill path would have to pick a stop. That is a flat fill
/// wearing a gradient's name, and it is what `c04eedb4` did. Instead a gradient is
/// its own paint and `draw` hands the stops to Core Graphics, which is where the
/// interpolation and the geometry belong.
package struct GradientPaint: ResolvedPaint {
    package var gradient: ResolvedGradient
    /// Whether the gradient keeps painting before its start and after its end.
    package var extendsBeforeStart: Bool
    package var extendsAfterEnd: Bool

    package init(
        _ gradient: ResolvedGradient,
        extendsBeforeStart: Bool = true,
        extendsAfterEnd: Bool = true
    ) {
        self.gradient = gradient
        self.extendsBeforeStart = extendsBeforeStart
        self.extendsAfterEnd = extendsAfterEnd
    }

    /// Only a gradient whose every stop is fully opaque paints opaquely, the same
    /// rule the solid path uses.
    package var isOpaque: Bool {
        !gradient.stops.isEmpty && gradient.stops.allSatisfy { $0.color.opacity == 1 }
    }

    /// True when no part of the gradient is visible.
    ///
    /// `Color.Resolved` reports clear at zero opacity, since one colour is the whole
    /// of it. A gradient is clear when every stop is transparent, because then there
    /// is no point along the axis that would put anything down. An empty gradient has
    /// no stops and paints nothing, so it is clear for the same reason.
    package var isClear: Bool {
        gradient.stops.allSatisfy(\.color.isClear)
    }

    /// Not compatible with a CALayer.
    ///
    /// The layer path fills a view with `backgroundColor` and `contents`, which are
    /// single colours, so a gradient taken that way would have to collapse to a stop
    /// again. `DisplayListViewCache` reads this to send the item through a drawing
    /// group instead, where the paint is handed to the context intact.
    package var isCALayerCompatible: Bool { false }

    /// No leaf tag.
    ///
    /// `CodableResolvedPaint` reserves `linearGradient` (2) and `radialGradient` (3)
    /// for exactly this, but the protocol requires the tag to be `static`, so it
    /// cannot see the instance's kind and would have to claim one tag for both
    /// gradients and be wrong half the time. Returning nil sends encoding through
    /// `encode(to:)`, which writes nothing, rather than mislabelling a radial
    /// gradient as a linear one. Claiming both tags properly needs a per-kind
    /// message, which is a change to `CodableResolvedPaint` and out of scope here.
    package static var leafProtobufTag: CodableResolvedPaint.Tag? { nil }

    /// Encodes nothing.
    ///
    /// A paint only reaches this when a display list is serialised, which the
    /// drawing path does not do, and the stops' encoding is not written yet.
    /// Encoding an empty container is the protocol's own way of saying "nothing to
    /// put here"; throwing instead would turn a missing feature into a crash on
    /// every serialisation, and encoding one stop as if it were the whole gradient
    /// would be a lie a decoder could not detect.
    package func encode(to encoder: inout ProtobufEncoder) throws {}

    package func draw(path: Path, style: PathDrawingStyle, in context: GraphicsContext, bounds: CGRect?) {
        #if canImport(Darwin)
        // No context is not a reason to paint something else. This is the same
        // situation as any other draw: there is nowhere to draw.
        guard let cgContext = context.cgContext else { return }

        let geometry = gradient.resolved(in: bounds ?? path.boundingRect)
        guard let cgGradient = GradientPaint.makeCGGradient(from: geometry) else {
            // A degenerate geometry has no axis to interpolate along. The shape is
            // left alone rather than filled with a colour nobody asked for.
            return
        }

        // CF_OPTIONS imports as a RawRepresentable here rather than as an
        // OptionSet, so the two flags are combined explicitly instead of through
        // `union` or `insert`.
        var rawOptions: UInt32 = 0
        if extendsBeforeStart { rawOptions |= 0x01 }
        if extendsAfterEnd { rawOptions |= 0x02 }
        // The raw initializer is failable in this SDK. There is no value of these
        // flags it could reject, but unwrapping it here rather than force-unwrapping
        // means a future SDK that does reject one leaves the shape unpainted instead
        // of trapping.
        guard let options = CGGradientDrawingOptions(rawValue: rawOptions) else {
            return
        }

        CGContextSaveGState(cgContext)
        defer { CGContextRestoreGState(cgContext) }

        // The extend options are what make Core Graphics paint outside the two
        // points; clipping to the path is a separate concern and does not extend a
        // run, it only limits it.
        CGContextAddPath(cgContext, path.cgPath)
        CGContextClip(cgContext)

        switch geometry.kind {
        case .linear:
            CGContextDrawLinearGradient(
                cgContext,
                cgGradient,
                geometry.startPoint,
                geometry.endPoint,
                options
            )
        case .radial:
            CGContextDrawRadialGradient(
                cgContext,
                cgGradient,
                geometry.startPoint,
                geometry.startRadius,
                geometry.endPoint,
                geometry.endRadius,
                options
            )
        }
        #else
        // Off Darwin there is no Core Graphics gradient to draw into. Failing loudly
        // beats painting a stand-in colour the caller never asked for; a platform
        // that wants gradients needs a real shading backend, not a substitute fill.
        _openSwiftUIUnimplementedFailure()
        #endif
    }

    #if canImport(Darwin)
    /// Builds the CGGradient for a resolved geometry.
    ///
    /// The stops are handed over as a flat component buffer, one RGBA quadruple per
    /// stop, with the matching locations.
    package static func makeCGGradient(from geometry: ResolvedGradient.Geometry) -> CGGradient? {
        guard !geometry.stops.isEmpty, !geometry.isDegenerate else { return nil }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        // The stops go over as a flat component buffer, not as CGColor objects.
        // CGGradientCreateWithColors identifies each element by its class and refuses
        // anything that is not an O2Color, and the object the CGColor initialiser
        // produces under this clang module is not recognised as one, so the gradient
        // came back NULL. The components entry point takes the colours as numbers and
        // builds the stops itself, so nothing of ours crosses that class check and
        // cocotron's validation of a CGColor array is left exactly as it was.
        var locations: [CGFloat] = []
        var components: [CGFloat] = []
        locations.reserveCapacity(geometry.stops.count)
        components.reserveCapacity(geometry.stops.count * 4)

        for stop in geometry.stops {
            // Color.Resolved stores linear components and its accessors are the sRGB
            // encoding of the same numbers. CoreGraphics takes the encoded
            // premultiplied form for a device-space gradient, so the accessors are
            // right here and the interpolation above used the linear ones.
            locations.append(stop.location)
            components.append(contentsOf: [
                CGFloat(stop.color.red),
                CGFloat(stop.color.green),
                CGFloat(stop.color.blue),
                CGFloat(stop.color.opacity),
            ])
        }

        // The create function already applied its +1, so the Unmanaged reference is taken here.
        return CGGradientCreateWithColorComponents(colorSpace, components, locations, geometry.stops.count)?.takeRetainedValue()
    }
    #endif
}
