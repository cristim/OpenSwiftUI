//
//  OpacityShapeStyleTests.swift
//  OpenSwiftUICoreTests

@testable import OpenSwiftUICore
import OpenSwiftUITestsSupport
import Testing

@Suite(.tags(.aigc))
struct OpacityShapeStyleTests {
    @Test
    func resolveStyleMultipliesNestedOpacities() {
        var shape = _ShapeStyle_Shape(
            operation: .resolveStyle(name: .foreground, levels: 0 ..< 1),
            environment: EnvironmentValues()
        )
        _OpacityShapeStyle(style: _OpacityShapeStyle(style: Color.red, opacity: 0.5), opacity: 0.5)._apply(to: &shape)
        #expect(shape.stylePack[.foreground, 0].opacity == 0.25)
    }

    @Test
    func fallbackColorAppliesOpacity() {
        var shape = _ShapeStyle_Shape(operation: .fallbackColor(level: 0), environment: EnvironmentValues())
        _OpacityShapeStyle(style: Color.red, opacity: 0.5)._apply(to: &shape)
        guard case let .color(color) = shape.result else {
            Issue.record("Expected a fallback color")
            return
        }
        #expect(color == Color.red.opacity(0.5))
    }
}
