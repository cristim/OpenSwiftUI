public import CoreGraphics

/// A gradient as a shape style.
///
/// `_apply(to:)` used to resolve to the first stop's colour, which is a flat fill
/// wearing a gradient's name: the stops after the first were never looked at, and
/// the geometry was never used. A gradient now carries itself as a paint through
/// the shape style pack, which has a paint slot for exactly this, so the stops and
/// the unit geometry survive all the way to the display list and from there into
/// Core Graphics.
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
        gradient._apply(
            kind: .linear,
            startPoint: startPoint,
            endPoint: endPoint,
            startRadius: 0,
            endRadius: 1,
            to: &shape
        )
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
        gradient._apply(
            kind: .radial,
            startPoint: center,
            endPoint: center,
            startRadius: startRadius,
            endRadius: endRadius,
            to: &shape
        )
    }
}

extension Gradient {
    /// The resolved gradient this describes, in unit space.
    package func resolved(
        kind: ResolvedGradient.Kind,
        startPoint: UnitPoint,
        endPoint: UnitPoint,
        startRadius: CGFloat,
        endRadius: CGFloat,
        in environment: EnvironmentValues,
        colorSpace: ResolvedGradient.ColorSpace = .device
    ) -> ResolvedGradient {
        ResolvedGradient(
            kind: kind,
            startPoint: startPoint,
            endPoint: endPoint,
            startRadius: startRadius,
            endRadius: endRadius,
            colorSpace: colorSpace,
            stops: self.stops.map {
                ResolvedGradient.Stop(
                    color: $0.color.resolve(in: environment),
                    location: $0.location
                )
            }
        )
    }

    /// Resolves this gradient as a shape style.
    ///
    /// The operations are the ones every `PrimitiveShapeStyle` handles, and they
    /// keep their existing meanings:
    ///
    /// - `resolveStyle` is where the gradient becomes a paint in the pack, which is
    ///   the only way a multi-colour style survives to the display list.
    /// - `prepareText` is left alone. Text is drawn by the text path, and the
    ///   colour a text run needs is a single colour, so this contributes nothing
    ///   rather than claiming to have prepared anything.
    /// - `fallbackColor` asks for one colour, and the first stop is the honest
    ///   answer: it is a colour this gradient actually contains. This is not the
    ///   path a drawn gradient takes, and it is not what replaced the old behaviour.
    package func _apply(
        kind: ResolvedGradient.Kind,
        startPoint: UnitPoint,
        endPoint: UnitPoint,
        startRadius: CGFloat,
        endRadius: CGFloat,
        to shape: inout _ShapeStyle_Shape
    ) {
        let paint = _AnyResolvedPaint(GradientPaint(resolved(
            kind: kind,
            startPoint: startPoint,
            endPoint: endPoint,
            startRadius: startRadius,
            endRadius: endRadius,
            in: shape.environment
        )))
        let gradientStyle = _ShapeStyle_Pack.Style(.paint(paint))

        switch shape.operation {
        // .primaryStyle is deliberately not handled. Result.style takes an
        // AnyShapeStyle and .style(_:name:level:) on the pack is a different
        // function that needs a name, so writing a pack here would mean inventing
        // a name the caller never gave. The resolveStyle path below is the one the
        // solid path uses and the one the display list consumes.
        case let .resolveStyle(name, levels):
            // Levels past the first are overridden by something the caller layered
            // on top, so the gradient is only offered where nothing else is.
            guard levels.lowerBound != levels.upperBound else { break }
            shape.stylePack[name, levels.lowerBound] = gradientStyle
        case let .fallbackColor(level):
            // The same expression the solid path uses, so a gradient behind a faded
            // layer fades exactly as a solid fill would. The first stop is a colour
            // this gradient actually contains; this answers `fallbackColor`'s
            // single-colour question and is not the path a drawn gradient takes.
            let color: Color = stops.first?.color ?? .clear
            shape.result = .color(shape.applyingOpacity(at: level, to: color))
        case .primaryStyle, .prepareText, .copyStyle, .modifyBackground, .multiLevel:
            break
        }
    }
}
