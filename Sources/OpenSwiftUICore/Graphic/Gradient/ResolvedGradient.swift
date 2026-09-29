//
//  ResolvedGradient.swift
//  OpenSwiftUICore
//
//  Audited for 6.0.87
//  Status: Gradient geometry, stops and interpolation
package import Foundation
public import CoreGraphics

/// A gradient whose colours and geometry have been resolved against the
/// environment, ready to be handed to a graphics context.
package struct ResolvedGradient: Equatable {
    /// Where the gradient runs, in the shape's own terms: a linear gradient by
    /// its two end points, a radial gradient by a centre and an inner and outer
    /// radius, both as fractions of the shape they fill.
    ///
    /// The fractions are kept rather than resolved points because a style is
    /// resolved before the shape it fills has its bounds, so the points can only
    /// be worked out where the bounds are known.
    package enum Kind: Equatable, Sendable {
        case linear(start: UnitPoint, end: UnitPoint)
        case radial(center: UnitPoint, startRadius: CGFloat, endRadius: CGFloat)
    }

    package struct Stop: Equatable, Sendable {
        package var color: Color.Resolved
        package var location: CGFloat

        package init(color: Color.Resolved, location: CGFloat) {
            self.color = color
            self.location = location
        }
    }

    /// The space the stop colours are interpolated in. CoreGraphics paints a
    /// gradient in the gradient's own colour space, so the choice here has to
    /// agree with the colour space the gradient is created with.
    package enum ColorSpace: Equatable, Sendable {
        case device
        case linear
        case perceptual

        func mix(
            _ lhs: Color.Resolved,
            _ rhs: Color.Resolved,
            by fraction: Float
        ) -> Color.Resolved {
            let amount = fraction.clamped(to: 0...1)
            func mix(_ a: Float, _ b: Float) -> Float {
                a + (b - a) * amount
            }
            switch self {
            case .device:
                return Color.Resolved(
                    red: mix(lhs.red, rhs.red),
                    green: mix(lhs.green, rhs.green),
                    blue: mix(lhs.blue, rhs.blue),
                    opacity: mix(lhs.opacity, rhs.opacity)
                )
            case .linear, .perceptual:
                // Both interpolate the linear components: in the device space the
                // components are the sRGB encoded values, and in the linear space
                // they are the linear ones. A perceptual space would need a
                // different transfer function, which is not implemented.
                return Color.Resolved(
                    linearRed: mix(lhs.linearRed, rhs.linearRed),
                    linearGreen: mix(lhs.linearGreen, rhs.linearGreen),
                    linearBlue: mix(lhs.linearBlue, rhs.linearBlue),
                    opacity: mix(lhs.opacity, rhs.opacity)
                )
            }
        }
    }

    package var stops: [Stop]
    package var kind: Kind
    package var colorSpace: ColorSpace
    /// The shape the gradient fills, which is what the fractions are relative to.
    package var bounds: CGRect

    package init(
        stops: [Stop],
        kind: Kind,
        bounds: CGRect = .zero,
        colorSpace: ColorSpace = .device
    ) {
        self.stops = stops
        self.kind = kind
        self.bounds = bounds
        self.colorSpace = colorSpace
    }

    /// The geometry CoreGraphics draws with, worked out against the shape's
    /// bounds. A radial gradient's radii are fractions of the shape's shorter
    /// side, which is how they are scaled into the shape being filled.
    package var geometry: (kind: Kind, start: CGPoint, end: CGPoint, startRadius: CGFloat, endRadius: CGFloat)? {
        let scale = min(bounds.width, bounds.height)
        switch kind {
        case let .linear(start, end):
            return (kind, start.location(in: bounds), end.location(in: bounds), 0, 0)
        case let .radial(center, startRadius, endRadius):
            return (kind, center.location(in: bounds), center.location(in: bounds), startRadius * scale, endRadius * scale)
        }
    }

    /// A gradient is clear only when every one of its stops is, because a
    /// gradient paints all of them.
    package var isClear: Bool {
        stops.allSatisfy { $0.color.opacity == 0 }
    }

    /// A gradient is opaque only when every one of its stops is, for the same
    /// reason.
    package var isOpaque: Bool {
        !stops.isEmpty && stops.allSatisfy { $0.color.opacity == 1 }
    }

    /// The colour at `location`, which is expected in `0...1`. Locations outside
    /// that range hold at the nearest stop, which is what CoreGraphics does with
    /// a draw that runs past the gradient's own ends.
    package func color(at location: CGFloat) -> Color.Resolved? {
        guard !stops.isEmpty else { return nil }
        guard stops.count > 1 else { return stops[0].color }

        // The last stop at or before the location, so coincident stops resolve to
        // the earlier colour rather than dividing by a zero length span.
        var index = 0
        for candidate in 1..<stops.count where stops[candidate].location <= location {
            index = candidate
        }
        guard index + 1 < stops.count else { return stops[index].color }

        let start = stops[index].location
        let end = stops[index + 1].location
        guard end > start else { return stops[index].color }

        let fraction = ((location - start) / (end - start)).clamped(to: 0...1)
        return colorSpace.mix(
            stops[index].color,
            stops[index + 1].color,
            by: Float(fraction)
        )
    }

    /// The CoreGraphics gradient for these stops.
    ///
    /// CoreGraphics takes a colour per stop and its location, and does the
    /// interpolation itself, so this is a straight transcription rather than a
    /// sampling of the interpolation above.
    package var cgGradient: CGGradient? {
        let space = CGColorSpaceCreateDeviceRGB()
        var components = [CGFloat]()
        components.reserveCapacity(stops.count * 4)
        for stop in stops {
            let color = stop.color
            components.append(CGFloat(color.red))
            components.append(CGFloat(color.green))
            components.append(CGFloat(color.blue))
            components.append(CGFloat(color.opacity))
        }
        var locations = [CGFloat]()
        locations.reserveCapacity(stops.count)
        var previous: CGFloat = 0
        for stop in stops {
            // CoreGraphics needs the locations ordered and within range; a stop
            // out of order would make it reject the whole gradient.
            let location = stop.location.clamped(to: previous...1)
            locations.append(location)
            previous = location
        }
        // The Create functions are imported as handing back an unmanaged
        // reference here rather than as an ARC managed one, so the reference is
        // taken here, once, instead of at every call site.
        guard let gradient = CGGradientCreateWithColorComponents(
            space, components, locations, stops.count
        )?.takeRetainedValue() else {
            return nil
        }
        return gradient
    }

    /// Draws the gradient with CoreGraphics' default options, which paint only
    /// between the gradient's own ends.
    package func draw(in context: CGContext) {
        // CoreGraphics' options import as a closed enum with no empty case, so
        // the value with no bits set is spelled through its raw value.
        draw(in: context, options: CGGradientDrawingOptions(rawValue: 0)!)
    }

    /// Draws the gradient into `context` with CoreGraphics' gradient drawing,
    /// which fills the current clip. Nothing is drawn when the gradient has no
    /// stops or CoreGraphics could not create one.
    package func draw(
        in context: CGContext,
        options: CGGradientDrawingOptions
    ) {
        guard let gradient = cgGradient,
              let geometry = geometry
        else {
            return
        }
        switch geometry.kind {
        case .linear:
            CGContextDrawLinearGradient(
                context,
                gradient,
                geometry.start,
                geometry.end,
                options
            )
        case .radial:
            CGContextDrawRadialGradient(
                context,
                gradient,
                geometry.start,
                geometry.startRadius,
                geometry.end,
                geometry.endRadius,
                options
            )
        }
    }
}

@frozen
public struct Gradient {
    @frozen
    public struct Stop {
        public var color: Color
        public var location: CGFloat

        public init(color: Color, location: CGFloat) {
            self.color = color
            self.location = location
        }
    }

    public var stops: [Stop]

    public init(stops: [Stop]) {
        self.stops = stops
    }

    public init(colors: [Color]) {
        let denominator = CGFloat(max(colors.count - 1, 1))
        self.stops = colors.enumerated().map { index, color in
            Stop(color: color, location: CGFloat(index) / denominator)
        }
    }

    package init(_ resolved: ResolvedGradient) {
        self.stops = []
    }
}
