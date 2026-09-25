@_spi(Private)
import OpenSwiftUICore

public struct _HoverRegionModifier: PrimitiveViewModifier {
    package var text: Text

    package init(text: Text) {
        self.text = text
    }

    nonisolated public static func _makeView(
        modifier _: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        body(_Graph(), inputs)
    }

    nonisolated public static func _makeViewList(
        modifier _: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        body(_Graph(), inputs)
    }
}

extension View {
    nonisolated public func help(_ text: LocalizedStringKey) -> some View {
        modifier(_HoverRegionModifier(text: Text(text)))
    }

    nonisolated public func help<S>(_ text: S) -> some View where S: StringProtocol {
        modifier(_HoverRegionModifier(text: Text(String(text))))
    }
}
