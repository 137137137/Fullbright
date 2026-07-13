//
//  BrightnessKeyManagerTests.swift
//  FullbrightTests
//
//  The CGEventTap callback itself needs a live tap to exercise, but the
//  event classification it relies on is pure and testable.
//

import CoreGraphics
import Testing
@testable import Fullbright

@MainActor
struct BrightnessKeyManagerTests {

    @Test("tap-disabled event types are recognized for re-enabling")
    func tapDisabledEvents_areRecognized() {
        #expect(BrightnessKeyManager.isTapDisabledEvent(.tapDisabledByTimeout))
        #expect(BrightnessKeyManager.isTapDisabledEvent(.tapDisabledByUserInput))
    }

    @Test("ordinary event types are not treated as tap-disabled")
    func ordinaryEvents_areNotTapDisabled() {
        #expect(!BrightnessKeyManager.isTapDisabledEvent(.keyDown))
        #expect(!BrightnessKeyManager.isTapDisabledEvent(.keyUp))
        #expect(!BrightnessKeyManager.isTapDisabledEvent(.null))
        #expect(!BrightnessKeyManager.isTapDisabledEvent(.flagsChanged))
    }
}
