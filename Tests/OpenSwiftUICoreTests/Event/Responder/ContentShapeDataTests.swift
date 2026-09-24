//
//  ContentShapeDataTests.swift
//  OpenSwiftUICoreTests

import Foundation
@_spi(ForOpenSwiftUIOnly) @testable import OpenSwiftUICore
import OpenSwiftUITestsSupport
import Testing

@Suite(.tags(.aigc))
struct ContentShapeDataTests {
    @Test
    func containsUsesShapeInLocalSize() {
        let data = ContentShapeData(shape: Ellipse(), eoFill: false)
        let points = [CGPoint(x: 50, y: 25), CGPoint(x: 2, y: 2), CGPoint(x: 99, y: 25)]
        let mask = points.withUnsafeBufferPointer {
            data.contains(points: $0, size: CGSize(width: 100, height: 50))
        }
        #expect(mask.rawValue == 0b101)
    }

    @Test
    func contentPathIsShapePathInLocalSize() {
        let data = ContentShapeData(shape: Rectangle(), eoFill: false)
        #expect(data.contentPath(size: CGSize(width: 30, height: 20)).boundingRect == CGRect(x: 0, y: 0, width: 30, height: 20))
    }
}
