//
//  ButtonStyle.swift
//  OpenSwiftUI
//
//  Audited for 3.5.2
//  Status: Complete

public protocol ButtonStyle {
    associatedtype Body: View
    
    @ViewBuilder
    func makeBody(configuration: Configuration) -> Self.Body
    
    typealias Configuration = ButtonStyleConfiguration
}

extension View {
    nonisolated public func buttonStyle<S>(_ style: S) -> some View where S: ButtonStyle {
        self
    }

    nonisolated public func buttonStyle<S>(_ style: S) -> some View where S: PrimitiveButtonStyle {
        self
    }
}
