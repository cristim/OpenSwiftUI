//
//  BlendModeEffect.swift
//  OpenSwiftUICore
//
//  Status: Complete

public import Foundation

// MARK: - _BlendModeEffect

@available(OpenSwiftUI_v1_0, *)
@frozen
public struct _BlendModeEffect: RendererEffect, Equatable {
    public var blendMode: BlendMode

    @inlinable
    nonisolated public init(blendMode: BlendMode) {
        self.blendMode = blendMode
    }

    package func effectValue(size: CGSize) -> DisplayList.Effect {
        .blendMode(GraphicsBlendMode(blendMode))
    }
}

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Sets the blend mode for compositing this view with overlapping views.
    ///
    /// - Parameter blendMode: The ``BlendMode`` for compositing this view.
    ///
    /// - Returns: A view that applies `blendMode` to this view.
    @inlinable
    nonisolated public func blendMode(_ blendMode: BlendMode) -> some View {
        modifier(_BlendModeEffect(blendMode: blendMode))
    }
}

// MARK: - _CompositingGroupEffect

@available(OpenSwiftUI_v1_0, *)
@frozen
public struct _CompositingGroupEffect: RendererEffect, Equatable {
    @inlinable
    nonisolated public init() {}

    package func effectValue(size: CGSize) -> DisplayList.Effect {
        .compositingGroup
    }
}

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Wraps this view in a compositing group.
    ///
    /// A compositing group makes compositing effects in this view's ancestor
    /// views, such as opacity and the blend mode, take effect before this view
    /// is rendered.
    ///
    /// - Returns: A view that wraps this view in a compositing group.
    @inlinable
    nonisolated public func compositingGroup() -> some View {
        modifier(_CompositingGroupEffect())
    }
}
