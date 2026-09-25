import CoreGraphics

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
        (gradient.stops.first?.color ?? .clear)._apply(to: &shape)
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
        (gradient.stops.first?.color ?? .clear)._apply(to: &shape)
    }
}
