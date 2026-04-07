//
//  XDRControllerTests.swift
//  FullbrightTests
//
//  Orchestration tests for XDRController using Core test doubles.
//  All tests pass supportsXDROverride to avoid touching SkyLight or
//  the real display configuration during init.
//

import Testing
@testable import Fullbright

@MainActor
@Suite("XDRController")
struct XDRControllerTests {

    private func makeController(
        supportsXDR: Bool = true,
        displayServices: StubDisplayServices = StubDisplayServices(),
        nightShift: StubNightShiftManager = StubNightShiftManager(),
        gamma: StubGammaTableManager = StubGammaTableManager(),
        configurator: StubDisplayConfigurator = StubDisplayConfigurator(),
        dirtyStore: StubXDRDirtyFlagStore = StubXDRDirtyFlagStore()
    ) -> (XDRController, StubDisplayServices, StubNightShiftManager, StubGammaTableManager, StubDisplayConfigurator, StubXDRDirtyFlagStore) {
        let controller = XDRController(
            displayID: 1,
            displayServices: displayServices,
            nightShiftManager: nightShift,
            gammaManager: gamma,
            displayConfigurator: configurator,
            dirtyFlagStore: dirtyStore,
            supportsXDROverride: supportsXDR
        )
        return (controller, displayServices, nightShift, gamma, configurator, dirtyStore)
    }

    @Test("enable sets the dirty flag, disable clears it")
    func enableDisable_updatesDirtyFlag() {
        let (controller, _, _, _, _, dirtyStore) = makeController()
        #expect(dirtyStore.isDirty == false)
        _ = controller.enableXDR()
        #expect(dirtyStore.isDirty == true)
        _ = controller.disableXDR()
        #expect(dirtyStore.isDirty == false)
    }

    @Test("display configurator is not invoked when supportsXDR override is supplied")
    func configurator_notCalledWhenOverrideGiven() {
        let configurator = StubDisplayConfigurator()
        let (_, _, _, _, configurator2, _) = makeController(configurator: configurator)
        #expect(configurator2.configureForXDRCalls.isEmpty)
    }

    @Test("init reads default gamma once")
    func init_readsDefaultGammaOnce() {
        let (_, _, _, gamma, _, _) = makeController()
        #expect(gamma.readDefaultGammaCount == 1)
    }

    @Test("isXDRSupported reflects the override")
    func supported_reflectsOverride() {
        let (capable, _, _, _, _, _) = makeController(supportsXDR: true)
        #expect(capable.isXDRSupported == true)

        let (incapable, _, _, _, _, _) = makeController(supportsXDR: false)
        #expect(incapable.isXDRSupported == false)
    }

    @Test("enableXDR returns false when XDR is not supported")
    func enableXDR_unsupported_returnsFalse() {
        let (controller, _, _, _, _, _) = makeController(supportsXDR: false)
        #expect(controller.enableXDR() == false)
        #expect(controller.isEnabled == false)
    }

    @Test("enableXDR snapshots pre-XDR brightness via getBrightness")
    func enableXDR_capturesHardwareBrightness() {
        let ds = StubDisplayServices()
        ds.storedBrightness = 0.42
        let (controller, _, _, _, _, _) = makeController(displayServices: ds)
        _ = controller.enableXDR()
        #expect(ds.getBrightnessCallCount >= 1)
    }

    @Test("enableXDR drives brightness to max and disables ambient light compensation")
    func enableXDR_maxesBrightnessAndDisablesALC() {
        let (controller, ds, _, _, _, _) = makeController()
        _ = controller.enableXDR()

        #expect(ds.storedBrightness == 1.0)
        #expect(ds.lastLinearBrightness == 1.0)
        #expect(ds.ambientLightCompensationEnabled == false)
    }

    @Test("enableXDR captures Night Shift state and disables it")
    func enableXDR_disablesNightShift() {
        let ns = StubNightShiftManager(startEnabled: true)
        let (controller, _, _, _, _, _) = makeController(nightShift: ns)
        _ = controller.enableXDR()

        #expect(ns.isEnabled == false)
        #expect(ns.setEnabledCalls == [false])
    }

    @Test("enableXDR sets isEnabled and returns true on supported hardware")
    func enableXDR_setsEnabledState() {
        let (controller, _, _, _, _, _) = makeController()
        #expect(controller.enableXDR() == true)
        #expect(controller.isEnabled == true)
    }

    @Test("disableXDR is a no-op when not currently enabled")
    func disableXDR_whileDisabled_returnsFalse() {
        let (controller, _, _, _, _, _) = makeController()
        #expect(controller.disableXDR() == false)
    }

    @Test("disableXDR stops the gamma render loop")
    func disableXDR_stopsGammaLoop() {
        let (controller, _, _, gamma, _, _) = makeController()
        _ = controller.enableXDR()
        gamma.stopRenderLoopCount = 0
        _ = controller.disableXDR()
        #expect(gamma.stopRenderLoopCount == 1)
    }

    @Test("disableXDR restores ambient light compensation")
    func disableXDR_restoresALC() {
        let (controller, ds, _, _, _, _) = makeController()
        _ = controller.enableXDR()
        _ = controller.disableXDR()
        #expect(ds.ambientLightCompensationEnabled == true)
    }

    @Test("disableXDR only restores Night Shift when it was previously on")
    func disableXDR_restoresNightShiftOnlyIfWasEnabled() {
        // Case A: was off → stays off.
        let nsOff = StubNightShiftManager(startEnabled: false)
        let (controllerA, _, _, _, _, _) = makeController(nightShift: nsOff)
        _ = controllerA.enableXDR()
        _ = controllerA.disableXDR()
        // Only the disable call at enableXDR should be in the list, not a re-enable.
        #expect(nsOff.setEnabledCalls == [false])

        // Case B: was on → gets re-enabled after disable.
        let nsOn = StubNightShiftManager(startEnabled: true)
        let (controllerB, _, _, _, _, _) = makeController(nightShift: nsOn)
        _ = controllerB.enableXDR()
        _ = controllerB.disableXDR()
        #expect(nsOn.setEnabledCalls == [false, true])
    }

    @Test("disableXDR restores pre-XDR brightness to a sensible value")
    func disableXDR_restoresBrightness() {
        let ds = StubDisplayServices()
        ds.storedBrightness = 0.65
        let (controller, _, _, _, _, _) = makeController(displayServices: ds)
        _ = controller.enableXDR()
        _ = controller.disableXDR()
        // Post-disable brightness should be approximately the pre-XDR value.
        #expect(ds.storedBrightness == 0.65)
    }

    @Test("disableXDR clears isEnabled")
    func disableXDR_clearsIsEnabled() {
        let (controller, _, _, _, _, _) = makeController()
        _ = controller.enableXDR()
        _ = controller.disableXDR()
        #expect(controller.isEnabled == false)
    }

    @Test("adjustBrightness is a no-op when XDR is off")
    func adjustBrightness_whenOff_doesNothing() {
        let (controller, _, _, gamma, _, _) = makeController()
        let before = controller.brightness
        controller.adjustBrightness(delta: 0.1)
        #expect(controller.brightness == before)
        #expect(gamma.updateBrightnessCalls.isEmpty)
    }

    @Test("adjustBrightness clamps to [0.0, 1.0] when XDR is on")
    func adjustBrightness_clampsToUnitInterval() {
        let (controller, _, _, _, _, _) = makeController()
        _ = controller.enableXDR()

        // enableXDR sets brightness = brightnessBeforeXDR * 0.5 = 0.5 * 0.5 = 0.25
        controller.adjustBrightness(delta: 2.0)
        #expect(controller.brightness == 1.0)

        controller.adjustBrightness(delta: -5.0)
        #expect(controller.brightness == 0.0)
    }

    @Test("adjustBrightness forwards unified brightness to gamma manager")
    func adjustBrightness_forwardsToGammaManager() {
        let (controller, _, _, gamma, _, _) = makeController()
        _ = controller.enableXDR()
        gamma.updateBrightnessCalls.removeAll()

        controller.adjustBrightness(delta: 0.1)
        #expect(gamma.updateBrightnessCalls.count == 1)
    }
}
