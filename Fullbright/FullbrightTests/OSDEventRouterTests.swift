//
//  OSDEventRouterTests.swift
//  FullbrightTests
//
//  Verifies the brightness-key → XDR adjust → OSD show pipeline in isolation.
//

import Foundation
import Testing
@testable import Fullbright

// StubBrightnessKeyManager is defined in ViewModelTestDoubles.swift so
// multiple test suites can share it.

@MainActor
@Suite("OSDEventRouter")
struct OSDEventRouterTests {

    private func makeSetup() -> (OSDEventRouter, XDRController, StubBrightnessKeyManager, StubOSDController) {
        let ds = StubDisplayServices()
        let gamma = StubGammaTableManager()
        let xdr = XDRController(
            displayID: 1,
            displayServices: ds,
            nightShiftManager: StubNightShiftManager(),
            gammaManager: gamma,
            displayConfigurator: StubDisplayConfigurator(),
            dirtyFlagStore: StubXDRDirtyFlagStore(),
            supportsXDROverride: true
        )
        let osd = StubOSDController()
        let router = OSDEventRouter(xdrController: xdr, osdController: osd)
        let keyManager = StubBrightnessKeyManager()
        return (router, xdr, keyManager, osd)
    }

    @Test("attach installs a brightness-key callback on the key manager")
    func attach_installsCallback() {
        let (router, _, keyManager, _) = makeSetup()
        #expect(keyManager.onBrightnessKey == nil)
        router.attach(to: keyManager)
        #expect(keyManager.onBrightnessKey != nil)
    }

    @Test("brightness-up key adjusts XDR brightness up by step value")
    func brightnessUp_increasesBrightness() {
        let (router, xdr, keyManager, osd) = makeSetup()
        _ = xdr.enableXDR()
        let before = xdr.brightness

        router.attach(to: keyManager)
        keyManager.onBrightnessKey?(true)  // isUp = true

        #expect(xdr.brightness > before)
        #expect(osd.showCallCount == 1)
    }

    @Test("brightness-down key adjusts XDR brightness down by step value")
    func brightnessDown_decreasesBrightness() {
        let (router, xdr, keyManager, osd) = makeSetup()
        _ = xdr.enableXDR()
        // Raise brightness first so there's headroom to go down.
        xdr.adjustBrightness(delta: 0.5)
        let before = xdr.brightness

        router.attach(to: keyManager)
        keyManager.onBrightnessKey?(false)  // isUp = false

        #expect(xdr.brightness < before)
        #expect(osd.showCallCount == 1)
    }

    @Test("detach clears the key manager callback")
    func detach_clearsCallback() {
        let (router, _, keyManager, _) = makeSetup()
        router.attach(to: keyManager)
        router.detach()
        #expect(keyManager.onBrightnessKey == nil)
    }

    @Test("re-attaching to a different key manager detaches the previous one")
    func reattach_detachesPrevious() {
        let (router, _, keyManagerA, _) = makeSetup()
        let keyManagerB = StubBrightnessKeyManager()

        router.attach(to: keyManagerA)
        #expect(keyManagerA.onBrightnessKey != nil)

        router.attach(to: keyManagerB)
        #expect(keyManagerA.onBrightnessKey == nil)
        #expect(keyManagerB.onBrightnessKey != nil)
    }
}
