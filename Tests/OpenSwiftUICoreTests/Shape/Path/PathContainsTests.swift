//
//  PathContainsTests.swift
//  OpenSwiftUICoreTests

import Foundation
@_spi(ForOpenSwiftUIOnly) @testable import OpenSwiftUICore
import OpenSwiftUITestsSupport
import Testing

@Suite(.tags(.aigc))
struct PathContainsTests {
    @Test(arguments: [
        (CGPoint(x: 10, y: 10), true),
        (CGPoint(x: 29.9, y: 19.9), true),
        (CGPoint(x: 30, y: 10), false),
        (CGPoint(x: 5, y: 15), false),
    ] as [(CGPoint, Bool)])
    func rect(point: CGPoint, expected: Bool) {
        #expect(Path(CGRect(x: 10, y: 10, width: 20, height: 10)).contains(point) == expected)
    }

    @Test(arguments: [
        (CGPoint(x: 20, y: 10), true),
        (CGPoint(x: 39, y: 10), true),
        (CGPoint(x: 40, y: 10), false),
        (CGPoint(x: 2, y: 2), false),
        (CGPoint(x: 20, y: 21), false),
    ] as [(CGPoint, Bool)])
    func ellipse(point: CGPoint, expected: Bool) {
        #expect(Path(ellipseIn: CGRect(x: 0, y: 0, width: 40, height: 20)).contains(point) == expected)
    }

    @Test
    func ellipseWithNegativeSizeIsStandardized() {
        #expect(Path(ellipseIn: CGRect(x: 40, y: 20, width: -40, height: -20)).contains(CGPoint(x: 20, y: 10)))
    }

    @Test(arguments: [
        (CGPoint(x: 1, y: 1), false),
        (CGPoint(x: 4, y: 4), true),
        (CGPoint(x: 50, y: 1), true),
        (CGPoint(x: 99, y: 49), false),
        (CGPoint(x: 50, y: 25), true),
    ] as [(CGPoint, Bool)])
    func roundedRect(point: CGPoint, expected: Bool) {
        let path = Path(roundedRect: CGRect(x: 0, y: 0, width: 100, height: 50), cornerRadius: 10, style: .circular)
        #expect(path.contains(point) == expected)
    }

    @Test
    func emptyPathContainsNothing() {
        #expect(Path().contains(.zero) == false)
    }

    @Test
    func pointsAreOffsetByOrigin() {
        let path = Path(CGRect(x: 0, y: 0, width: 10, height: 10))
        let mask = path.contains(
            points: [CGPoint(x: 105, y: 105), CGPoint(x: 5, y: 5)],
            origin: CGPoint(x: 100, y: 100)
        )
        #expect(mask.rawValue == 0b01)
    }
}
