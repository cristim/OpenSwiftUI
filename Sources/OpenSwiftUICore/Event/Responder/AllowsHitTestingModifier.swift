//
//  AllowsHitTestingModifier.swift
//  OpenSwiftUICore
//
//  Status: Complete

package import OpenAttributeGraphShims

// MARK: - _AllowsHitTestingModifier

@available(OpenSwiftUI_v1_0, *)
@frozen
public struct _AllowsHitTestingModifier: ViewModifier, Equatable, MultiViewModifier, PrimitiveViewModifier {
    public var allowsHitTesting: Bool

    @inlinable
    nonisolated public init(allowsHitTesting: Bool) {
        self.allowsHitTesting = allowsHitTesting
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
        let responder = AllowsHitTestingResponder(inputs: inputs)
        outputs.preferences.viewResponders = Attribute(
            AllowsHitTestingResponderFilter(
                modifier: modifier.value,
                children: .init(outputs.preferences.viewResponders),
                responder: responder
            )
        )
        return outputs
    }

    public typealias Body = Never
}

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Configures whether this view participates in hit test operations.
    ///
    /// - Parameter enabled: A Boolean value that indicates whether this view
    ///   and its subviews can be the target of hit testing.
    @inlinable
    nonisolated public func allowsHitTesting(_ enabled: Bool) -> some View {
        modifier(_AllowsHitTestingModifier(allowsHitTesting: enabled))
    }
}

// MARK: - AllowsHitTestingResponder

private final class AllowsHitTestingResponder: DefaultLayoutViewResponder {
    var isEnabled = true

    override var allowsHitTesting: Bool { isEnabled }

    override func containsGlobalPoints(
        _ points: [PlatformPoint],
        cacheKey: UInt32?,
        options: ViewResponder.ContainsPointsOptions
    ) -> ViewResponder.ContainsPointsResult {
        guard isEnabled else {
            return .init(mask: [], priority: .zero, children: children)
        }
        return super.containsGlobalPoints(points, cacheKey: cacheKey, options: options)
    }

    override func addContentPath(
        to path: inout Path,
        kind: ContentShapeKinds,
        in space: CoordinateSpace,
        observer: (any ContentPathObserver)?
    ) {
        guard isEnabled || kind != .interaction else {
            if let observer { addObserver(observer) }
            return
        }
        super.addContentPath(to: &path, kind: kind, in: space, observer: observer)
    }

    override func extendPrintTree(string: inout String) {
        string.append("allowsHitTesting \(isEnabled)")
    }
}

// MARK: - AllowsHitTestingResponderFilter

private struct AllowsHitTestingResponderFilter: StatefulRule {
    @Attribute var modifier: _AllowsHitTestingModifier
    @OptionalAttribute var children: [ViewResponder]?
    let responder: AllowsHitTestingResponder

    typealias Value = [ViewResponder]

    func updateValue() {
        let isEnabled = modifier.allowsHitTesting
        if responder.isEnabled != isEnabled {
            responder.isEnabled = isEnabled
            responder.childrenDidChange()
        }
        if let (children, changed) = $children?.changedValue(), changed {
            responder.children = children
        }
        if !hasValue {
            value = [responder]
        }
    }
}
