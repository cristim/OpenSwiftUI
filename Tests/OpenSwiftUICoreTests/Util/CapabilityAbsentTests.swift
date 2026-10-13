//
//  CapabilityAbsentTests.swift
//  OpenSwiftUICoreTests

import OpenSwiftUICore
import Testing

struct CapabilityAbsentTests {
    @Test
    func repeatedReportDoesNotTrap() {
        _darlingCapabilityAbsent("testCapability")
        _darlingCapabilityAbsent("testCapability")
    }
}
