import OpenSwiftUICore

public protocol TextFieldStyle {}

public struct PlainTextFieldStyle: TextFieldStyle {
    public init() {}
}

extension View {
    nonisolated public func textFieldStyle<S>(_ style: S) -> some View where S: TextFieldStyle {
        self
    }

    nonisolated public func focused(_ binding: FocusState<Bool>.Binding) -> some View {
        self
    }
}
