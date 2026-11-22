//
//  NSAttributedString+Key.swift
//  OpenSwiftUICore
//
//  Status: Darwin gap fill
//

// Foundation's Swift overlay declares the nested key name, and this platform's does not:
// cocotron's Foundation has the top-level `NSAttributedStringKey` typedef and nothing that
// maps it to `NSAttributedString.Key`. Swift code here spells it the Apple way, and a
// missing type is a compile error rather than a runtime one.
public import Foundation

extension NSAttributedString {
    public typealias Key = NSAttributedStringKey
}
