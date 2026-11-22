//
//  Compatibility.swift
//  OpenSwiftUICore
//
//  The platform gap fills this package needs, in one place.
//

// Re-exported rather than imported privately: a fill for a missing Foundation type is
// only useful if everything downstream can see it, and every consumer of this package
// needs the same fills.
@_exported import OpenSwiftUICompatibility

// Core Graphics re-exported once, here, rather than imported in the 146 files that use
// CGPoint, CGSize, CGRect and friends. Those files rely on the types arriving
// transitively, and where that stops working every one of them breaks at once, which is a
// worse failure than a missing import in a single file would be.
@_exported import CoreGraphics
