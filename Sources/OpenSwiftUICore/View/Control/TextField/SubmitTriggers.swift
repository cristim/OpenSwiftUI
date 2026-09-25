public struct SubmitTriggers: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let text = SubmitTriggers(rawValue: 1 << 0)
    public static let search = SubmitTriggers(rawValue: 1 << 1)
}

package struct SubmitAction {
    package var triggers: SubmitTriggers
    package var action: () -> Void
}

private struct SubmitActionKey: EnvironmentKey {
    static var defaultValue: SubmitAction? { nil }
}

extension EnvironmentValues {
    package var submitAction: SubmitAction? {
        get { self[SubmitActionKey.self] }
        set { self[SubmitActionKey.self] = newValue }
    }
}

extension View {
    nonisolated public func onSubmit(
        of triggers: SubmitTriggers = .text,
        _ action: @escaping () -> Void
    ) -> some View {
        environment(\.submitAction, SubmitAction(triggers: triggers, action: action))
    }
}
