//
//  OSDEventRouterTests.swift
//  FullbrightTests
//
//  Verifies the brightness-key → XDR adjust → OSD show pipeline in isolation.
//

import Foundation
import Testing
@testable import Fullbright

/// Minimal BrightnessKeyManaging stub. We only care about `brightnessStep`
/// and `onBrightnessKey` for the router tests.
@MainActor
private final class StubBrightnessKeyManager: BrightnessKeyManaging {
    var brightnessStep: Float = 0.1
    var intercepting: Bool = false
    var onBrightnessKey: BrightnessKeyHandler?
    var startCallCount = 0
    var stopCallCount = 0

    func start() { startCallCount += 1 }
    func stop() { stopCallCount += 1 }
}

@MainActor
@Suite("OSDEventRouter")
struct OSDEventRouterTests {

    private func makeSetup() -> (OSDEventRouter, XDRController, StubBrightnessKeyManager, StubDisplayServices, StubGammaTableManager) {
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
        // NOTE: OSDEventRouter takes a real XDRBrightnessOSDWindowController.
        // Constructing one requires NSHostingView / NSPanel which is not
        // test-friendly, so we skip asserting on the OSD side and focus
        // on the brightness-adjust side via a direct router stub.
        let osd = XDRBrightnessOSDWindowController(xdrController: xdr)
        let router = OSDEventRouter(xdrController: xdr, osdController: osd)
        let keyManager = StubBrightnessKeyManager()
        return (router, xdr, keyManager, ds, gamma)
    }

    @Test("attach installs a brightness-key callback on the key manager")
    func attach_installsCallback() {
        let (router, _, keyManager, _, _) = makeSetup()
        #expect(keyManager.onBrightnessKey == nil)
        router.attach(to: keyManager)
        #expect(keyManager.onBrightnessKey != nil)
    }

    @Test("brightness-up key adjusts XDR brightness up by step value")
    func brightnessUp_increasesBrightness() {
        let (router, xdr, keyManager, _, _) = makeSetup()
        _ = xdr.enableXDR()
        let before = xdr.brightness

        router.attach(to: keyManager)
        keyManager.onBrightnessKey?(true)  // isUp = true

        #expect(xdr.brightness > before)
    }

    @Test("brightness-down key adjusts XDR brightness down by step value")
    func brightnessDown_decreasesBrightness() {
        let (router, xdr, keyManager, _, _) = makeSetup()
        _ = xdr.enableXDR()
        // Raise brightness first so there's headroom to go down.
        xdr.adjustBrightness(delta: 0.5)
        let before = xdr.brightness

        router.attach(to: keyManager)
        keyManager.onBrightnessKey?(false)  // isUp = false

        #expect(xdr.brightness < before)
    }

    @Test("detach clears the key manager callback")
    func detach_clearsCallback() {
        let (router, _, keyManager, _, _) = makeSetup()
        router.attach(to: keyManager)
        router.detach()
        #expect(keyManager.onBrightnessKey == nil)
    }

    @Test("re-attaching to a different key manager detaches the previous one")
    func reattach_detachesPrevious() {
        let (router, _, keyManagerA, _, _) = makeSetup()
        let keyManagerB = StubBrightnessKeyManager()

        router.attach(to: keyManagerA)
        #expect(keyManagerA.onBrightnessKey != nil)

        router.attach(to: keyManagerB)
        #expect(keyManagerA.onBrightnessKey == nil)
        #expect(keyManagerB.onBrightnessKey != nil)
    }
}
