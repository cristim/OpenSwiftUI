//
//  ContentShapeModifier.swift
//  OpenSwiftUICore
//
//  Status: Complete

package import Foundation
package import OpenAttributeGraphShims

// MARK: - _ContentShapeModifier

@available(OpenSwiftUI_v1_0, *)
@frozen
public struct _ContentShapeModifier<ContentShape>: ViewModifier, MultiViewModifier, PrimitiveViewModifier where ContentShape: Shape {
    public var shape: ContentShape

    public var eoFill: Bool

    @inlinable
    nonisolated public init(shape: ContentShape, eoFill: Bool = false) {
        self.shape = shape
        self.eoFill = eoFill
    }

    nonisolated public static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        var outputs = body(_Graph(), inputs)
        guard inputs.preferences.requiresViewResponders else {
            return outputs
        }
        let responder = ContentShapeResponder<ContentShape>(inputs: inputs)
        outputs.preferences.viewResponders = Attribute(
            ContentShapeResponderFilter(
                modifier: modifier.value,
                children: .init(outputs.preferences.viewResponders),
                size: inputs.animatedSize(),
                position: inputs.animatedPosition(),
                transform: inputs.transform,
                responder: responder
            )
        )
        return outputs
    }

    public typealias Body = Never
}

@available(*, unavailable)
extension _ContentShapeModifier: Sendable {}

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Defines the content shape for hit testing.
    ///
    /// - Parameters:
    ///   - shape: The hit testing shape for the view.
    ///   - eoFill: A Boolean that indicates whether the shape is interpreted
    ///     with the even-odd winding number rule.
    ///
    /// - Returns: A view that uses the given shape for hit testing.
    @inlinable
    nonisolated public func contentShape<S>(_ shape: S, eoFill: Bool = false) -> some View where S: Shape {
        modifier(_ContentShapeModifier(shape: shape, eoFill: eoFill))
    }
}

// MARK: - ContentShapeData

private struct ContentShapeData<ContentShape>: ContentResponder where ContentShape: Shape {
    var shape: ContentShape
    var eoFill: Bool

    func contains(points: UnsafeBufferPointer<PlatformPoint>, size: CGSize) -> BitVector64 {
        contentPath(size: size).contains(points: points, eoFill: eoFill)
    }

    func contentPath(size: CGSize) -> Path {
        shape.effectivePath(in: CGRect(origin: .zero, size: size))
    }
}

// MARK: - ContentShapeResponder

/// Hit tests against the content shape instead of the union of the
/// children, while still offering the children as hit-test targets.
private final class ContentShapeResponder<ContentShape>: DefaultLayoutViewResponder where ContentShape: Shape {
    var helper = ContentResponderHelper<ContentShapeData<ContentShape>>()

    override func containsGlobalPoints(
        _ points: [PlatformPoint],
        cacheKey: UInt32?,
        options: ViewResponder.ContainsPointsOptions
    ) -> ViewResponder.ContainsPointsResult {
        helper.containsGlobalPoints(points, cacheKey: cacheKey, options: options, children: children)
    }

    override func addContentPath(
        to path: inout Path,
        kind: ContentShapeKinds,
        in space: CoordinateSpace,
        observer: (any ContentPathObserver)?
    ) {
        if kind == .interaction || !_SemanticFeature_v3.isEnabled {
            helper.addContentPath(to: &path, kind: kind, in: space, observer: observer)
        } else {
            super.addContentPath(to: &path, kind: kind, in: space, observer: observer)
        }
    }

    override func extendPrintTree(string: inout String) {
        string.append("contentShape \(ContentShape.self) [\(helper.size.width), \(helper.size.height)]")
    }
}

// MARK: - ContentShapeResponderFilter

private struct ContentShapeResponderFilter<ContentShape>: StatefulRule where ContentShape: Shape {
    @Attribute var modifier: _ContentShapeModifier<ContentShape>
    @OptionalAttribute var children: [ViewResponder]?
    @Attribute var size: ViewSize
    @Attribute var position: ViewOrigin
    @Attribute var transform: ViewTransform
    let responder: ContentShapeResponder<ContentShape>

    typealias Value = [ViewResponder]

    func updateValue() {
        let (modifier, modifierChanged) = $modifier.changedValue()
        responder.helper.update(
            data: (ContentShapeData(shape: modifier.shape, eoFill: modifier.eoFill), modifierChanged),
            size: $size.changedValue(),
            position: $position.changedValue(),
            transform: $transform.changedValue(),
            parent: responder
        )
        if let (children, changed) = $children?.changedValue(), changed {
            responder.children = children
        }
        if !hasValue {
            value = [responder]
        }
    }
}
