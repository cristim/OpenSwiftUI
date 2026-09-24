//
//  MaskEffect.swift
//  OpenSwiftUICore
//
//  Status: Complete

public import Foundation
package import OpenAttributeGraphShims

// MARK: - _MaskEffect

@available(OpenSwiftUI_v1_0, *)
@frozen
public struct _MaskEffect<Mask>: ViewModifier, MultiViewModifier, PrimitiveViewModifier where Mask: View {
    public var mask: Mask

    @inlinable
    nonisolated public init(mask: Mask) {
        self.mask = mask
    }

    nonisolated public static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        makeMaskView(
            mask: modifier[offset: { .of(&$0.mask) }].value,
            alignment: nil,
            inputs: inputs,
            body: body
        )
    }

    public typealias Body = Never
}

@available(*, unavailable)
extension _MaskEffect: Sendable {}

@available(OpenSwiftUI_v1_0, *)
extension _MaskEffect: Equatable where Mask: Equatable {
    nonisolated public static func == (a: _MaskEffect<Mask>, b: _MaskEffect<Mask>) -> Bool {
        a.mask == b.mask
    }
}

// MARK: - _MaskAlignmentEffect

@available(OpenSwiftUI_v3_0, *)
@frozen
public struct _MaskAlignmentEffect<Mask>: ViewModifier, MultiViewModifier, PrimitiveViewModifier where Mask: View {
    public var alignment: Alignment

    public var mask: Mask

    @inlinable
    nonisolated public init(alignment: Alignment, mask: Mask) {
        self.alignment = alignment
        self.mask = mask
    }

    nonisolated public static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        makeMaskView(
            mask: modifier[offset: { .of(&$0.mask) }].value,
            alignment: modifier[offset: { .of(&$0.alignment) }].value,
            inputs: inputs,
            body: body
        )
    }

    public typealias Body = Never
}

@available(*, unavailable)
extension _MaskAlignmentEffect: Sendable {}

// MARK: - View + mask

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Masks this view using the alpha channel of the given view.
    ///
    /// - Parameter mask: The view whose alpha the rendering system applies to
    ///   the specified view.
    @available(*, deprecated, message: "Use overload where mask accepts a @ViewBuilder instead.")
    @inlinable
    nonisolated public func mask<Mask>(_ mask: Mask) -> some View where Mask: View {
        modifier(_MaskEffect(mask: mask))
    }
}

@available(OpenSwiftUI_v3_0, *)
extension View {
    /// Masks this view using the alpha channel of the given view.
    ///
    /// The mask is sized and positioned like an overlay: `alignment` places it
    /// when its size differs from the size of this view.
    ///
    /// - Parameters:
    ///   - alignment: The alignment for `mask` in relation to this view.
    ///   - mask: The view whose alpha the rendering system applies to
    ///     the specified view.
    @inlinable
    nonisolated public func mask<Mask>(
        alignment: Alignment = .center,
        @ViewBuilder _ mask: () -> Mask
    ) -> some View where Mask: View {
        modifier(_MaskAlignmentEffect(alignment: alignment, mask: mask()))
    }
}

// MARK: - makeMaskView

/// Lays the mask out like an overlay of the content; when a display list is
/// requested, the mask's display list becomes the content's `.mask` effect.
private func makeMaskView<Mask>(
    mask: Attribute<Mask>,
    alignment: Attribute<Alignment>?,
    inputs: _ViewInputs,
    body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
) -> _ViewOutputs where Mask: View {
    let effect = inputs.preferences.requiresDisplayList ? Attribute(MaskEffectValue(mask: .init())) : nil
    let makeContent = { (inputs: _ViewInputs) -> _ViewOutputs in
        var inputs = inputs
        inputs.base.pushStableIndex(0)
        let outputs = body(_Graph(), inputs)
        var maskInputs = inputs
        maskInputs.preferences = PreferencesInputs(hostKeys: inputs.preferences.hostKeys)
        maskInputs.preferences.requiresDisplayList = effect != nil
        let maskOutputs = makeSecondaryLayer(
            secondaryLayer: mask,
            alignment: alignment,
            primaryOutputs: outputs,
            inputs: maskInputs
        )
        effect?.mutateBody(as: MaskEffectValue.self, invalidating: true) { value in
            value.$mask = maskOutputs.displayList
        }
        return outputs
    }
    guard let effect else {
        return makeContent(inputs)
    }
    return MaskDisplayListEffect._makeRendererEffect(effect: _GraphValue(effect), inputs: inputs) { _, inputs in
        makeContent(inputs)
    }
}

// MARK: - MaskDisplayListEffect

private struct MaskDisplayListEffect: RendererEffect {
    var mask: DisplayList

    func effectValue(size: CGSize) -> DisplayList.Effect {
        .mask(mask)
    }
}

private struct MaskEffectValue: Rule, AsyncAttribute {
    @OptionalAttribute var mask: DisplayList?

    var value: MaskDisplayListEffect {
        MaskDisplayListEffect(mask: mask ?? DisplayList())
    }
}
