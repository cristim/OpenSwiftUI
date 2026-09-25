#if os(macOS)
import AppKit
#endif
import OpenSwiftUICore

public struct TextField<Label>: View where Label: View {
    @Binding private var text: String
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
        AppKitTextField(text: $text, onEditingChanged: onEditingChanged, onCommit: onCommit)
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

    func makeNSView(context: Context) -> NSTextField {
        let view = NSTextField()
        view.setDelegate(context.coordinator)
        return view
    }

    func updateNSView(_ view: NSTextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onEditingChanged = onEditingChanged
        context.coordinator.onCommit = onCommit
        if view.stringValue() != text {
            view.setStringValue(text)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onEditingChanged: onEditingChanged, onCommit: onCommit)
    }

    final class Coordinator: PlatformViewCoordinator {
        var text: Binding<String>
        var onEditingChanged: (Bool) -> Void
        var onCommit: () -> Void

        init(
            text: Binding<String>,
            onEditingChanged: @escaping (Bool) -> Void,
            onCommit: @escaping () -> Void
        ) {
            self.text = text
            self.onEditingChanged = onEditingChanged
            self.onCommit = onCommit
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
            onCommit()
        }
    }
}
#endif
