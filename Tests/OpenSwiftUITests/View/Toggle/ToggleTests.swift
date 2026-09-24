//
//  ToggleTests.swift
//  OpenSwiftUITests

@testable import OpenSwiftUI
import OpenSwiftUITestsSupport
import Testing

@MainActor
@Suite(.tags(.aigc))
struct ToggleTests {
    @Test
    func titleKeyLabelAndBinding() {
        var isOn = false
        let binding = Binding(get: { isOn }, set: { isOn = $0 })
        let toggle = Toggle("Enabled", isOn: binding)
        #expect(toggle.label == Text("Enabled"))
        #expect(toggle.toggleState == .off)
        toggle.toggleState = .on
        #expect(isOn)
    }

    @Test
    func stringTitleLabel() {
        let title: Substring = "Verbatim"
        let toggle = Toggle(title, isOn: .constant(true))
        #expect(toggle.label == Text(verbatim: "Verbatim"))
        #expect(toggle.toggleState == .on)
    }
}
