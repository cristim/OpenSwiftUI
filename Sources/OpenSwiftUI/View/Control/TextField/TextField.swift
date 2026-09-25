#if os(macOS)
import AppKit
#endif
import OpenSwiftUICore

public struct TextField<Label>: View where Label: View {
    @Binding private var text: String
    @Environment(\.submitAction) private var submitAction
    private var label: Label
    private var onEditingChanged: (Bool) -> Void
    private var onCommit: () -> Void

    private init(
        text: Binding<String>,
        label: Label,
        onEditingChanged: @escaping (Bool) -> Void,
        onCommit: @escaping () -> Void
    ) {
        self._text = text
        self.label = label
        self.onEditingChanged = onEditingChanged
        self.onCommit = onCommit
    }

    public var body: some View {
        #if os(macOS)
        AppKitTextField(
            text: $text,
            onEditingChanged: onEditingChanged,
            onCommit: onCommit,
            onSubmit: submitAction?.triggers.contains(.text) == true ? submitAction?.action : nil
        )
        #else
        label
        #endif
    }
}

extension TextField where Label == Text {
    public init(
        _ titleKey: LocalizedStringKey,
        text: Binding<String>,
        onEditingChanged: @escaping (Bool) -> Void = { _ in },
        onCommit: @escaping () -> Void = {}
    ) {
        self.init(
            text: text,
            label: Text(titleKey),
            onEditingChanged: onEditingChanged,
            onCommit: onCommit
        )
    }
}

#if os(macOS)
private struct AppKitTextField: NSViewRepresentable {
    @Binding var text: String
    var onEditingChanged: (Bool) -> Void
    var onCommit: () -> Void
    var onSubmit: (() -> Void)?

    func makeNSView(context: Context) -> NSTextField {
        let view = NSTextField()
        view.setDelegate(context.coordinator)
        return view
    }

    func updateNSView(_ view: NSTextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onEditingChanged = onEditingChanged
        context.coordinator.onCommit = onCommit
        context.coordinator.onSubmit = onSubmit
        if view.stringValue() != text {
            view.setStringValue(text)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onEditingChanged: onEditingChanged, onCommit: onCommit, onSubmit: onSubmit)
    }

    final class Coordinator: PlatformViewCoordinator {
        var text: Binding<String>
        var onEditingChanged: (Bool) -> Void
        var onCommit: () -> Void
        var onSubmit: (() -> Void)?

        init(
            text: Binding<String>,
            onEditingChanged: @escaping (Bool) -> Void,
            onCommit: @escaping () -> Void,
            onSubmit: (() -> Void)?
        ) {
            self.text = text
            self.onEditingChanged = onEditingChanged
            self.onCommit = onCommit
            self.onSubmit = onSubmit
        }

        @objc override func controlTextDidBeginEditing(_ notification: Notification) {
            onEditingChanged(true)
        }

        @objc override func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue() ?? ""
        }

        @objc override func controlTextDidEndEditing(_ notification: Notification) {
            onEditingChanged(false)
            // AppKit uses 0x10 for Return; losing focus or pressing Tab is not a submit.
            if (notification.userInfo?["NSTextMovement"] as? Int) == 0x10 {
                onCommit()
                onSubmit?()
            }
        }
    }
}
#endif
