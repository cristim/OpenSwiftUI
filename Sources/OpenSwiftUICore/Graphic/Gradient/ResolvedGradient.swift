//
//  ResolvedGradient.swift
//  OpenSwiftUICore
//

//  Audited for 6.0.87
//  Status: Complete

public import CoreGraphics

/// A gradient resolved against an environment but not yet against a shape.
///
/// The geometry is kept in unit space on purpose. A gradient is built once and
/// painted at many sizes, so resampling its stops for each size would be wrong, and
/// storing absolute points would make it depend on where the shape happens to be.
/// `resolved(in:)` turns the unit geometry into concrete points at draw time, from
/// the bounds of the shape actually being filled.
package struct ResolvedGradient: Equatable {
    package enum Kind: Equatable {
        /// A gradient along the line from `startPoint` to `endPoint`.
        case linear
        /// A gradient along the radius from `startPoint`, between the two radii.
        case radial
    }

    package struct Stop: Equatable {
        package var color: Color.Resolved
        /// Where the stop sits along the gradient: 0 at the start, 1 at the end.
        package var location: CGFloat

        package init(color: Color.Resolved, location: CGFloat) {
            self.color = color
            self.location = location
        }
    }

    package var kind: Kind
    /// Start of a linear gradient, or centre of a radial one, in unit space.
    package var startPoint: UnitPoint
    /// End of a linear gradient, in unit space. Unused for a radial gradient.
    package var endPoint: UnitPoint
    /// Radii of a radial gradient, as fractions of the bounds' larger side.
    package var startRadius: CGFloat
    package var endRadius: CGFloat
    package var colorSpace: ColorSpace
    package var stops: [Stop]

    package init(
        kind: Kind,
        startPoint: UnitPoint,
        endPoint: UnitPoint,
        startRadius: CGFloat,
        endRadius: CGFloat,
        colorSpace: ColorSpace,
        stops: [Stop]
    ) {
        self.kind = kind
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.startRadius = startRadius
        self.endRadius = endRadius
        self.colorSpace = colorSpace
        self.stops = stops.constrainedLocations()
    }

    package static func == (a: ResolvedGradient, b: ResolvedGradient) -> Bool {
        a.kind == b.kind
            && a.startPoint == b.startPoint
            && a.endPoint == b.endPoint
            && a.startRadius == b.startRadius
            && a.endRadius == b.endRadius
            && a.colorSpace == b.colorSpace
            && a.stops == b.stops
    }
}

extension Array where Element == ResolvedGradient.Stop {
    /// Clamps every location into 0...1 and makes the sequence non-decreasing.
    ///
    /// Core Graphics constrains out-of-range and unordered locations rather than
    /// refusing the gradient, and so does this. Making them non-decreasing also means
    /// two stops at the same location resolve to the earlier colour instead of
    /// dividing by a zero-length span later.
    fileprivate func constrainedLocations() -> [ResolvedGradient.Stop] {
        var previous: CGFloat = 0
        var result: [ResolvedGradient.Stop] = []
        result.reserveCapacity(self.count)

        for stop in self {
            var location = stop.location
            if !(location >= 0) { location = 0 }
            if location > 1 { location = 1 }
            if location < previous { location = previous }
            previous = location
            result.append(ResolvedGradient.Stop(color: stop.color, location: location))
        }

        return result
    }
}

extension ResolvedGradient {
    /// A gradient with concrete geometry, ready to hand to Core Graphics.
    package struct Geometry: Equatable {
        package var kind: Kind
        package var startPoint: CGPoint
        package var endPoint: CGPoint
        package var startRadius: CGFloat
        package var endRadius: CGFloat
        package var colorSpace: ResolvedGradient.ColorSpace
        package var stops: [ResolvedGradient.Stop]

        /// A geometry with no axis to interpolate along: a linear gradient whose two
        /// points coincide, or a radial one whose end radius is not past its start.
        /// Core Graphics paints nothing useful for either, so they are refused
        /// rather than turned into a solid fill.
        package var isDegenerate: Bool {
            switch kind {
            case .linear:
                return startPoint == endPoint
            case .radial:
                return !(endRadius > startRadius)
            }
        }
    }

    /// Resolves the unit geometry against the bounds of the shape being filled.
    package func resolved(in bounds: CGRect) -> Geometry {
        // Unit radii are fractions of the larger side, so a radial gradient stays
        // circular in a non-square shape rather than becoming an ellipse.
        let extent = max(bounds.width, bounds.height)

        return Geometry(
            kind: kind,
            startPoint: bounds.point(at: startPoint),
            endPoint: bounds.point(at: endPoint),
            startRadius: startRadius * extent,
            endRadius: endRadius * extent,
            colorSpace: colorSpace,
            stops: stops
        )
    }
}

extension CGRect {
    /// Maps a unit point onto this rectangle.
    ///
    /// SwiftUI's unit space has its origin at the top left with y growing downward,
    /// while Core Graphics user space has y growing upward, so y is flipped here
    /// once rather than at every call site.
    fileprivate func point(at unit: UnitPoint) -> CGPoint {
        CGPoint(
            x: minX + CGFloat(unit.x) * width,
            y: minY + (1 - CGFloat(unit.y)) * height
        )
    }
}

extension ResolvedGradient {
    package enum ColorSpace: Equatable {
        case device
        case linear
        case perceptual

        /// Interpolates between two resolved colours in this space.
        ///
        /// Both cases interpolate the same components; they differ only in what
        /// those components already are. `Color.Resolved` stores linear components,
        /// and its sRGB accessors are the encoded form of the same numbers, so
        /// interpolating the linear components is correct for either space and
        /// mixing in the encoded form would darken the midpoint of every ramp.
        ///
        /// `.perceptual` has no implementation. It fails loudly instead of quietly
        /// interpolating in another space, because a caller that asked for
        /// perceptual and silently got sRGB gets colours it did not ask for with
        /// nothing in the result to say so.
        /// The fraction is a `Float`, not a `CGFloat`.
        ///
        /// `ModifiedColor.resolve(in:)` calls this with a `Float` fraction, and
        /// `Color.Resolved`'s components are `Float` too, so `Float` is the type
        /// the rest of the graph already uses. Changing it to `CGFloat` compiles
        /// here in isolation and then breaks every other caller with a type
        /// mismatch, so the existing signature is kept and converted at the edges
        /// that think in `CGFloat`.
        package func mix(
            _ lhs: Color.Resolved,
            _ rhs: Color.Resolved,
            by fraction: Float
        ) -> Color.Resolved {
            switch self {
            case .device, .linear:
                return Color.Resolved(
                    linearRed: lhs.linearRed + (rhs.linearRed - lhs.linearRed) * fraction,
                    linearGreen: lhs.linearGreen + (rhs.linearGreen - lhs.linearGreen) * fraction,
                    linearBlue: lhs.linearBlue + (rhs.linearBlue - lhs.linearBlue) * fraction,
                    opacity: lhs.opacity + (rhs.opacity - lhs.opacity) * fraction
                )
            case .perceptual:
                _openSwiftUIUnimplementedFailure()
            }
        }
    }
}

extension ResolvedGradient.Geometry {
    /// The colour at `t`, in 0...1.
    ///
    /// This is what the drawing path hands to Core Graphics, stop by stop; having
    /// it here as well means the interpolation can be checked directly, without a
    /// pixel buffer, and a caller that needs one colour from a gradient, for a
    /// legend or a placeholder, gets the same answer the pixels do.
    package func color(at t: CGFloat) -> Color.Resolved? {
        guard let first = stops.first, let last = stops.last else { return nil }

        var position = t
        if !(position >= 0) { position = 0 }
        if position > 1 { position = 1 }
        if position <= first.location { return first.color }
        if position >= last.location { return last.color }

        var upper = 1
        while upper < stops.count && stops[upper].location < position {
            upper += 1
        }
        let lower = upper - 1
        let lowerStop = stops[lower]
        let upperStop = stops[upper]
        let span = upperStop.location - lowerStop.location

        // Coincident stops have nothing to interpolate between; the earlier colour
        // wins, which is the same tie-break the drawing path gets.
        guard span > 0 else { return lowerStop.color }

        return colorSpace.mix(
            lowerStop.color,
            upperStop.color,
            by: Float((position - lowerStop.location) / span)
        )
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
