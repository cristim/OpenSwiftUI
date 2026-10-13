//
//  ChameleonFallbackTests.swift
//  OpenSwiftUITests

#if os(macOS) && OPENSWIFTUI_NO_CACHAMELEONLAYER
import AppKit
@_spi(ForOpenSwiftUIOnly)
@_spi(DisplayList_ViewSystem)
@testable import OpenSwiftUI
import OpenSwiftUICore
import Testing

@MainActor
struct ChameleonFallbackTests {
    @Test
    func chameleonColorFallsBackToGraphicsView() {
        let view = NSViewPlatformViewDefinition.makeView(kind: .chameleonColor)
        #expect(view is _NSGraphicsView)
    }
}
#endif
