public import CoreGraphics
public struct LinearGradient: PrimitiveShapeStyle, View {
    public var gradient: Gradient
    public var startPoint: UnitPoint
    public var endPoint: UnitPoint
    public init(gradient: Gradient, startPoint: UnitPoint, endPoint: UnitPoint) {
        self.gradient = gradient
        self.startPoint = startPoint
        self.endPoint = endPoint
    }
    public typealias Body = _ShapeView<Rectangle, Self>
    public func _apply(to shape: inout _ShapeStyle_Shape) {
        let resolved = ResolvedGradient(
            stops: gradient.stops.map {
                ResolvedGradient.Stop(
                    color: $0.color.resolve(in: shape.environment),
                    location: $0.location
                )
            },
            kind: .linear(start: startPoint, end: endPoint),
            bounds: shape.bounds ?? .zero
        )
        shape._applyGradient(resolved)
    }
}

public struct RadialGradient: PrimitiveShapeStyle, View {
    public var gradient: Gradient
    public var center: UnitPoint
    public var startRadius: CGFloat
    public var endRadius: CGFloat
    public init(gradient: Gradient, center: UnitPoint, startRadius: CGFloat, endRadius: CGFloat) {
        self.gradient = gradient
        self.center = center
        self.startRadius = startRadius
        self.endRadius = endRadius
    }
    public typealias Body = _ShapeView<Rectangle, Self>
    public func _apply(to shape: inout _ShapeStyle_Shape) {
        let resolved = ResolvedGradient(
            stops: gradient.stops.map {
                ResolvedGradient.Stop(
                    color: $0.color.resolve(in: shape.environment),
                    location: $0.location
                )
            },
            kind: .radial(
                center: center,
                startRadius: startRadius,
                endRadius: endRadius
            ),
            bounds: shape.bounds ?? .zero
        )
        shape._applyGradient(resolved)
    }
}

extension UnitPoint {
    /// The point this unit point names inside `rect`. A unit point's y grows
    /// downward, matching the rect's own orientation, so the two are laid out the
    /// same way and no flip is needed.
    package func location(in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + x * rect.width,
            y: rect.minY + y * rect.height
        )
    }
}

extension _ShapeStyle_Shape {
    /// Stores a gradient as this shape's fill, on the same path a solid colour
    /// takes, so the rest of the style resolution does not have to know that a
    /// gradient is a fill like any other.
    package mutating func _applyGradient(_ gradient: ResolvedGradient) {
        switch operation {
        case let .resolveStyle(name, levels):
            guard levels.lowerBound != levels.upperBound else {
                break
            }
            stylePack[name, levels.lowerBound] = .init(
                .paint(_AnyResolvedPaint(GradientPaint(gradient: gradient)))
            )
        default:
            break
        }
    }
}
