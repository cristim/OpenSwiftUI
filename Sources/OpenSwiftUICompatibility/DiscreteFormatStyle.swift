//
//  DiscreteFormatStyle.swift
//  OpenSwiftUI_SPI
//
//  Status: Darwin gap fill
//

/// A format that turns a value of `FormatInput` into `FormatOutput`.
///
/// Foundation declares this, and Darwin needs it for `TimeDataFormatting` and
/// `DiscreteFormatStyle.Format(_:locale:)`. It is declared here because the platform this
/// package currently builds against does not provide it, and a missing protocol is a
/// compile error rather than a runtime one.
///
/// The two associated types are the primary ones, so a conforming type can be written
/// `DiscreteFormatStyle<Input, Output>`.
public import Foundation

package protocol DiscreteFormatStyle<FormatInput, FormatOutput> {
    associatedtype FormatInput
    associatedtype FormatOutput

    func format(_ value: FormatInput) -> FormatOutput
    func format(_ value: FormatInput, locale: Locale) -> FormatOutput
}

extension DiscreteFormatStyle {
    package func callAsFunction(_ value: FormatInput) -> FormatOutput {
        format(value)
    }
}
