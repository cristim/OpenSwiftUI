//
//  RendererEffectModifierTests.swift
//  OpenSwiftUICoreTests

import Foundation
import OpenAttributeGraphShims
@testable import OpenSwiftUICore
import OpenSwiftUITestsSupport
import Testing

@MainActor
@Suite(.disabled(if: attributeGraphVendor == .oag), .tags(.aigc))
struct RendererEffectModifierTests {
    private func displayList<V: View>(_ view: V) -> String {
        let graph = ViewGraph(rootViewType: V.self, requestedOutputs: [.layout, .displayList])
        graph.instantiateOutputs()
        graph.setRootView(view)
        graph.setProposedSize(CGSize(width: 100, height: 100))
        return graph.displayList().0.description
    }

    // A translucent mask keeps canonicalization from folding the mask into a clip.
    @Test
    func alignedMaskIsPlacedLikeAnOverlay() throws {
        struct ContentView: View {
            var body: some View {
                Color.red
                    .frame(width: 100, height: 100)
                    .mask(alignment: .topLeading) {
                        Color.black.opacity(0.5).frame(width: 40, height: 20)
                    }
            }
        }
        let regex = try Regex(#"\(mask\s+\(item [^\n]*\s+\(frame \(0\.0 0\.0; 40\.0 20\.0\)\)"#)
        #expect(displayList(ContentView()).contains(regex))
    }

    @Test
    func maskIsCenteredByDefault() throws {
        struct ContentView: View {
            var body: some View {
                Color.red
                    .frame(width: 100, height: 100)
                    .modifier(_MaskEffect(mask: Color.black.opacity(0.5).frame(width: 40, height: 20)))
            }
        }
        let regex = try Regex(#"\(mask\s+\(item [^\n]*\s+\(frame \(30\.0 40\.0; 40\.0 20\.0\)\)"#)
        #expect(displayList(ContentView()).contains(regex))
    }

    @Test
    func blendModeAndCompositingGroupEffects() {
        struct ContentView: View {
            var body: some View {
                Color.red
                    .frame(width: 100, height: 100)
                    .blendMode(.multiply)
                    .compositingGroup()
            }
        }
        let description = displayList(ContentView())
        #expect(description.contains("#:compositing-group"))
        #expect(description.contains("#:blend-mode"))
    }
}
