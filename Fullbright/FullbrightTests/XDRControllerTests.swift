//
//  XDRControllerTests.swift
//  FullbrightTests
//
//  Orchestration tests for XDRController using Core test doubles.
//  All tests pass supportsXDROverride to avoid touching SkyLight or
//  the real display configuration during init, and inject millisecond
//  timings so the EDR engagement state machine can be exercised quickly.
//

import Foundation
import Testing
@testable import Fullbright

@MainActor
@Suite("XDRController")
struct XDRControllerTests {

    /// Millisecond-scale timings so engage/cooldown/monitor phases run
    /// inside test budgets.
    static let testTiming = XDRTiming(
        engagePollInterval: .milliseconds(5),
        engageTimeout: .milliseconds(80),
        retryCooldown: .milliseconds(40),
        monitorInterval: .milliseconds(10),
        brightnessFadeDuration: 0,
        keyFadeDuration: 0
    )

    struct Harness {
        let controller: XDRController
        let displayServices: StubDisplayServices
        let nightShift: StubNightShiftManager
        let gamma: StubGammaTableManager
        let configurator: StubDisplayConfigurator
        let dirtyStore: StubXDRDirtyFlagStore
        let edrSignal: StubEDRSignal
        let lifecycle: StubDisplayLifecycleObserver
        let events: RecordedEvents
        let restoreColorSyncCount: () -> Int
    }

    private func makeHarness(
        supportsXDR: Bool = true,
        displayServices: StubDisplayServices = StubDisplayServices(),
        nightShift: StubNightShiftManager = StubNightShiftManager(),
        gamma: StubGammaTableManager = StubGammaTableManager(),
        timing: XDRTiming = testTiming
    ) -> Harness {
        let configurator = StubDisplayConfigurator()
        let dirtyStore = StubXDRDirtyFlagStore()
        let edrSignal = StubEDRSignal()
        let lifecycle = StubDisplayLifecycleObserver()
        let events = RecordedEvents()
        displayServices.eventLog = events
        gamma.eventLog = events

        let restoreCounter = Counter()
        let controller = XDRController(
            displayID: 1,
            displayServices: displayServices,
            nightShiftManager: nightShift,
            gammaManager: gamma,
            displayConfigurator: configurator,
            dirtyFlagStore: dirtyStore,
            edrSignal: edrSignal,
            lifecycleObserver: lifecycle,
            timing: timing,
            restoreColorSync: { restoreCounter.value += 1 },
            supportsXDROverride: supportsXDR
        )
        return Harness(
            controller: controller,
            displayServices: displayServices,
            nightShift: nightShift,
            gamma: gamma,
            configurator: configurator,
            dirtyStore: dirtyStore,
            edrSignal: edrSignal,
            lifecycle: lifecycle,
            events: events,
            restoreColorSyncCount: { restoreCounter.value }
        )
    }

    @MainActor
    final class Counter {
        var value = 0
    }

    /// Polls `condition` until it holds or the timeout elapses. The
    /// timeout is generous because the whole suite runs concurrently on
    /// the main actor — synchronous crypto/keychain tests can starve
    /// these polls for seconds at a time.
    @discardableResult
    private func waitUntil(
        timeoutMs: Int = 10000,
        _ condition: @MainActor () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + .milliseconds(timeoutMs)
        while clock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    // MARK: - Basic orchestration

    @Test("enable sets the dirty flag, disable clears it")
    func enableDisable_updatesDirtyFlag() {
        let h = makeHarness()
        #expect(h.dirtyStore.isDirty == false)
        _ = h.controller.enableXDR()
        #expect(h.dirtyStore.isDirty == true)
        _ = h.controller.disableXDR()
        #expect(h.dirtyStore.isDirty == false)
    }

    @Test("display configurator is not invoked when supportsXDR override is supplied")
    func configurator_notCalledWhenOverrideGiven() {
        let h = makeHarness()
        #expect(h.configurator.configureForXDRCalls.isEmpty)
    }

    @Test("init reads default gamma once")
    func init_readsDefaultGammaOnce() {
        let h = makeHarness()
        #expect(h.gamma.readDefaultGammaCount == 1)
    }

    @Test("init wires and starts the display lifecycle observer")
    func init_startsLifecycleObserver() {
        let h = makeHarness()
        #expect(h.lifecycle.startCount == 1)
        #expect(h.lifecycle.onScreensSleep != nil)
        #expect(h.lifecycle.onWake != nil)
        #expect(h.lifecycle.onDisplayParametersChanged != nil)
    }

    @Test("isXDRSupported reflects the override")
    func supported_reflectsOverride() {
        let capable = makeHarness(supportsXDR: true)
        #expect(capable.controller.isXDRSupported == true)

        let incapable = makeHarness(supportsXDR: false)
        #expect(incapable.controller.isXDRSupported == false)
    }

    @Test("enableXDR returns false when XDR is not supported")
    func enableXDR_unsupported_returnsFalse() {
        let h = makeHarness(supportsXDR: false)
        #expect(h.controller.enableXDR() == false)
        #expect(h.controller.isEnabled == false)
    }

    @Test("enableXDR snapshots pre-XDR brightness via getBrightness")
    func enableXDR_capturesHardwareBrightness() {
        let ds = StubDisplayServices()
        ds.storedBrightness = 0.42
        let h = makeHarness(displayServices: ds)
        _ = h.controller.enableXDR()
        #expect(ds.getBrightnessCallCount >= 1)
    }

    @Test("enableXDR drives brightness to max and disables ambient light compensation")
    func enableXDR_maxesBrightnessAndDisablesALC() {
        let h = makeHarness()
        _ = h.controller.enableXDR()

        #expect(h.displayServices.storedBrightness == 1.0)
        #expect(h.displayServices.lastLinearBrightness == 1.0)
        #expect(h.displayServices.ambientLightCompensationEnabled == false)
    }

    @Test("enableXDR applies compensating gamma BEFORE maxing the backlight")
    func enableXDR_compensatesBeforeBacklightJump() {
        let ds = StubDisplayServices()
        ds.storedLinearBrightness = 0.4
        let h = makeHarness(displayServices: ds)
        _ = h.controller.enableXDR()

        let gammaIndex = h.events.firstIndex(withPrefix: "applyScaledGamma")
        let backlightIndex = h.events.firstIndex(withPrefix: "setBrightness(1.0)")
        #expect(gammaIndex != nil)
        #expect(backlightIndex != nil)
        if let gammaIndex, let backlightIndex {
            #expect(gammaIndex < backlightIndex)
        }
        // The compensation equals the linear luminance fraction.
        #expect(h.gamma.applyScaledGammaCalls.first?.softwareBrightness == 0.4)
    }

    @Test("enableXDR falls back to a perceptual approximation when linear brightness is unavailable")
    func enableXDR_compensationFallback() {
        let ds = StubDisplayServices()
        ds.storedBrightness = 0.5
        ds.storedLinearBrightness = nil
        let h = makeHarness(displayServices: ds)
        _ = h.controller.enableXDR()
        // 0.5^2 = 0.25 gamma-2 approximation
        #expect(h.gamma.applyScaledGammaCalls.first?.softwareBrightness == 0.25)
    }

    @Test("enableXDR re-captures the gamma baseline after disabling Night Shift")
    func enableXDR_recapturesBaseline() {
        let h = makeHarness()
        #expect(h.gamma.readDefaultGammaCount == 1)
        _ = h.controller.enableXDR()
        #expect(h.gamma.readDefaultGammaCount == 2)
    }

    @Test("enableXDR captures Night Shift state and disables it")
    func enableXDR_disablesNightShift() {
        let ns = StubNightShiftManager(startEnabled: true)
        let h = makeHarness(nightShift: ns)
        _ = h.controller.enableXDR()

        #expect(ns.isEnabled == false)
        #expect(ns.setEnabledCalls == [false])
    }

    @Test("enableXDR sets isEnabled and returns true on supported hardware")
    func enableXDR_setsEnabledState() {
        let h = makeHarness()
        #expect(h.controller.enableXDR() == true)
        #expect(h.controller.isEnabled == true)
    }

    @Test("disableXDR is a no-op when not currently enabled")
    func disableXDR_whileDisabled_returnsFalse() {
        let h = makeHarness()
        #expect(h.controller.disableXDR() == false)
    }

    @Test("disableXDR stops gamma activity")
    func disableXDR_stopsGammaActivity() {
        let h = makeHarness()
        _ = h.controller.enableXDR()
        h.gamma.stopGammaActivityCount = 0
        _ = h.controller.disableXDR()
        #expect(h.gamma.stopGammaActivityCount == 1)
    }

    @Test("disableXDR restores ambient light compensation")
    func disableXDR_restoresALC() {
        let h = makeHarness()
        _ = h.controller.enableXDR()
        _ = h.controller.disableXDR()
        #expect(h.displayServices.ambientLightCompensationEnabled == true)
    }

    @Test("disableXDR only restores Night Shift when it was previously on")
    func disableXDR_restoresNightShiftOnlyIfWasEnabled() {
        // Case A: was off → stays off.
        let nsOff = StubNightShiftManager(startEnabled: false)
        let hA = makeHarness(nightShift: nsOff)
        _ = hA.controller.enableXDR()
        _ = hA.controller.disableXDR()
        // Only the disable call at enableXDR should be in the list, not a re-enable.
        #expect(nsOff.setEnabledCalls == [false])

        // Case B: was on → gets re-enabled after disable.
        let nsOn = StubNightShiftManager(startEnabled: true)
        let hB = makeHarness(nightShift: nsOn)
        _ = hB.controller.enableXDR()
        _ = hB.controller.disableXDR()
        #expect(nsOn.setEnabledCalls == [false, true])
    }

    @Test("disableXDR restores pre-XDR brightness to a sensible value")
    func disableXDR_restoresBrightness() {
        let ds = StubDisplayServices()
        ds.storedBrightness = 0.65
        let h = makeHarness(displayServices: ds)
        _ = h.controller.enableXDR()
        _ = h.controller.disableXDR()
        // Post-disable brightness should be approximately the pre-XDR value.
        #expect(ds.storedBrightness == 0.65)
    }

    @Test("disableXDR clears isEnabled and returns to idle")
    func disableXDR_clearsIsEnabled() {
        let h = makeHarness()
        _ = h.controller.enableXDR()
        _ = h.controller.disableXDR()
        #expect(h.controller.isEnabled == false)
        #expect(h.controller.engagementState == .idle)
    }

    @Test("adjustBrightness is a no-op when XDR is off")
    func adjustBrightness_whenOff_doesNothing() {
        let h = makeHarness()
        let before = h.controller.brightness
        h.controller.adjustBrightness(delta: 0.1)
        #expect(h.controller.brightness == before)
        #expect(h.gamma.fadeCalls.isEmpty)
    }

    @Test("adjustBrightness clamps to [0.0, 1.0] when XDR is on")
    func adjustBrightness_clampsToUnitInterval() {
        let h = makeHarness()
        _ = h.controller.enableXDR()

        h.controller.adjustBrightness(delta: 2.0)
        #expect(h.controller.brightness == 1.0)

        h.controller.adjustBrightness(delta: -5.0)
        #expect(h.controller.brightness == 0.0)
    }

    @Test("adjustBrightness fades gamma toward the new target")
    func adjustBrightness_fadesGamma() {
        let h = makeHarness()
        _ = h.controller.enableXDR()
        h.gamma.fadeCalls.removeAll()

        h.controller.adjustBrightness(delta: 0.1)
        #expect(h.gamma.fadeCalls.count == 1)
    }

    // MARK: - EDR engagement state machine

    @Test("engagement waits for headroom, then activates and fades to peak")
    func engage_activatesWhenHeadroomGranted() async {
        let h = makeHarness()
        _ = h.controller.enableXDR()
        #expect(h.controller.engagementState == .engaging)

        h.edrSignal.currentHeadroomValue = 2.0
        let active = await waitUntil { h.controller.engagementState == .active }
        #expect(active)

        // First engage jumps to peak (user asked for XDR) and fades gamma
        // to an unclamped (>1.0) target.
        #expect(h.controller.brightness == 1.0)
        let sawXDRTarget = await waitUntil { h.gamma.fadeCalls.contains { $0.target > 1.0 } }
        #expect(sawXDRTarget)
        #expect(h.gamma.startIntegrityMonitoringCount >= 1)
        #expect(!h.gamma.updateEDRHeadroomCalls.isEmpty)
    }

    @Test("engagement timeout enters cooldown, then retries and succeeds")
    func engage_timeoutCoolsDownThenRetries() async {
        let h = makeHarness()
        _ = h.controller.enableXDR()

        // Headroom never granted → cooldown after the (80ms) timeout.
        let cooledDown = await waitUntil { h.controller.engagementState == .cooldown }
        #expect(cooledDown)

        // Grant headroom during cooldown → next engage attempt succeeds.
        h.edrSignal.currentHeadroomValue = 2.0
        let active = await waitUntil { h.controller.engagementState == .active }
        #expect(active)
    }

    @Test("gamma target is clamped to SDR while EDR is not yet engaged")
    func adjust_whileEngaging_clampsToSDR() {
        let h = makeHarness()
        _ = h.controller.enableXDR()
        #expect(h.controller.engagementState == .engaging)
        h.gamma.fadeCalls.removeAll()

        // Stub maps unified 0.8 → software 1.6; the clamp caps it at 1.0.
        h.controller.adjustBrightness(delta: 0.8 - h.controller.brightness)
        #expect(h.gamma.fadeCalls.count == 1)
        #expect(h.gamma.fadeCalls.last?.target == 1.0)
    }

    @Test("headroom revocation clamps to SDR and re-engages; recovery keeps user brightness")
    func monitor_headroomLoss_reengagesWithoutPeakJump() async {
        let h = makeHarness()
        _ = h.controller.enableXDR()
        h.edrSignal.currentHeadroomValue = 2.0
        let active = await waitUntil { h.controller.engagementState == .active }
        #expect(active)

        // User dials brightness down.
        h.controller.adjustBrightness(delta: -0.4)
        let userBrightness = h.controller.brightness

        // Headroom revoked → back to engaging with a clamped fade.
        h.edrSignal.currentHeadroomValue = 1.0
        let reengaging = await waitUntil { h.controller.engagementState == .engaging }
        #expect(reengaging)
        if let lastFade = h.gamma.fadeCalls.last {
            #expect(lastFade.target <= 1.0)
        }

        // Headroom returns → active again, brightness NOT re-jumped to peak.
        h.edrSignal.currentHeadroomValue = 2.0
        let reactivated = await waitUntil { h.controller.engagementState == .active }
        #expect(reactivated)
        #expect(h.controller.brightness == userBrightness)
    }

    @Test("user adjustment during engage suppresses the jump-to-peak")
    func engage_userAdjustmentWins() async {
        let h = makeHarness()
        _ = h.controller.enableXDR()
        #expect(h.controller.engagementState == .engaging)

        h.controller.adjustBrightness(delta: 0.3 - h.controller.brightness)
        let chosen = h.controller.brightness

        h.edrSignal.currentHeadroomValue = 2.0
        let active = await waitUntil { h.controller.engagementState == .active }
        #expect(active)
        #expect(h.controller.brightness == chosen)
    }

    @Test("headroom growth while active triggers a re-fade")
    func monitor_headroomChange_refades() async {
        let h = makeHarness()
        _ = h.controller.enableXDR()
        h.edrSignal.currentHeadroomValue = 1.6
        let active = await waitUntil { h.controller.engagementState == .active }
        #expect(active)

        let fadesBefore = h.gamma.fadeCalls.count
        let headroomCallsBefore = h.gamma.updateEDRHeadroomCalls.count
        h.edrSignal.currentHeadroomValue = 2.4
        let refaded = await waitUntil {
            h.gamma.fadeCalls.count > fadesBefore
                && h.gamma.updateEDRHeadroomCalls.count > headroomCallsBefore
        }
        #expect(refaded)
    }

    @Test("disable stops the engagement loop — later headroom changes are ignored")
    func disable_stopsEngagement() async {
        let h = makeHarness()
        _ = h.controller.enableXDR()
        h.edrSignal.currentHeadroomValue = 2.0
        let active = await waitUntil { h.controller.engagementState == .active }
        #expect(active)

        _ = h.controller.disableXDR()
        #expect(h.controller.engagementState == .idle)

        let fadesAfterDisable = h.gamma.fadeCalls.count
        h.edrSignal.currentHeadroomValue = 3.0
        try? await Task.sleep(for: .milliseconds(80))
        #expect(h.gamma.fadeCalls.count == fadesAfterDisable)
        #expect(h.controller.engagementState == .idle)
    }

    // MARK: - Smooth disable

    /// Timing with a real (small) fade so the smooth-disable path runs.
    static let smoothTiming = XDRTiming(
        engagePollInterval: .milliseconds(5),
        engageTimeout: .milliseconds(80),
        retryCooldown: .milliseconds(40),
        monitorInterval: .milliseconds(10),
        brightnessFadeDuration: 0.05,
        keyFadeDuration: 0
    )

    @Test("smooth disable fades gamma down before restoring the backlight")
    func disable_smooth_fadesBeforeRestore() async {
        let ds = StubDisplayServices()
        ds.storedBrightness = 0.65
        ds.storedLinearBrightness = 0.4
        let h = makeHarness(displayServices: ds, timing: Self.smoothTiming)
        _ = h.controller.enableXDR()
        #expect(ds.storedBrightness == 1.0)

        h.gamma.fadeCalls.removeAll()
        _ = h.controller.disableXDR()

        // Immediately after: XDR reads as off, the fade toward the pre-XDR
        // luminance has started, but the backlight/dirty-flag teardown has
        // not happened yet.
        #expect(h.controller.isEnabled == false)
        #expect(h.gamma.fadeCalls.last?.target == 0.4)
        #expect(ds.storedBrightness == 1.0)
        #expect(h.dirtyStore.isDirty == true)

        // After the fade window, the full teardown lands.
        let restored = await waitUntil { ds.storedBrightness == 0.65 }
        #expect(restored)
        #expect(h.dirtyStore.isDirty == false)
    }

    @Test("immediate disable tears down synchronously")
    func disable_immediate_isSynchronous() {
        let ds = StubDisplayServices()
        ds.storedBrightness = 0.65
        let h = makeHarness(displayServices: ds, timing: Self.smoothTiming)
        _ = h.controller.enableXDR()

        _ = h.controller.disableXDR(immediate: true)
        #expect(ds.storedBrightness == 0.65)
        #expect(h.dirtyStore.isDirty == false)
    }

    @Test("re-enabling during a smooth disable completes the teardown first, then enables")
    func disable_thenQuickReenable_isConsistent() async {
        let ds = StubDisplayServices()
        ds.storedBrightness = 0.65
        let h = makeHarness(displayServices: ds, timing: Self.smoothTiming)
        _ = h.controller.enableXDR()

        _ = h.controller.disableXDR()
        #expect(h.controller.isEnabled == false)
        _ = h.controller.enableXDR()

        #expect(h.controller.isEnabled == true)
        #expect(ds.storedBrightness == 1.0)
        #expect(h.dirtyStore.isDirty == true)

        // The cancelled teardown must not fire later and yank the display
        // out from under the re-enabled session.
        try? await Task.sleep(for: .milliseconds(150))
        #expect(h.controller.isEnabled == true)
        #expect(ds.storedBrightness == 1.0)
        #expect(h.dirtyStore.isDirty == true)
    }

    // MARK: - Gamma conflict escalation

    @Test("persistent gamma conflict disables XDR")
    func gammaConflict_disablesXDR() async {
        let h = makeHarness()
        _ = h.controller.enableXDR()
        #expect(h.controller.isEnabled == true)

        h.gamma.onPersistentGammaConflict?()
        #expect(h.controller.isEnabled == false)
        #expect(h.controller.engagementState == .idle)
    }

    // MARK: - Display lifecycle

    @Test("screens sleeping restores gamma and pauses engagement")
    func lifecycle_sleepRestoresGamma() async {
        let h = makeHarness()
        _ = h.controller.enableXDR()
        h.edrSignal.currentHeadroomValue = 2.0
        let active = await waitUntil { h.controller.engagementState == .active }
        #expect(active)

        let restoresBefore = h.restoreColorSyncCount()
        h.gamma.stopGammaActivityCount = 0
        h.lifecycle.fireScreensSleep()

        #expect(h.restoreColorSyncCount() == restoresBefore + 1)
        #expect(h.gamma.stopGammaActivityCount == 1)
    }

    @Test("wake re-captures baseline, re-asserts backlight, and re-engages")
    func lifecycle_wakeReengages() async {
        let h = makeHarness()
        _ = h.controller.enableXDR()
        h.edrSignal.currentHeadroomValue = 2.0
        let active = await waitUntil { h.controller.engagementState == .active }
        #expect(active)

        h.lifecycle.fireScreensSleep()
        // Simulate the OS dropping headroom and backlight during sleep.
        h.edrSignal.currentHeadroomValue = 1.0
        h.displayServices.storedBrightness = 0.3

        let baselineReadsBefore = h.gamma.readDefaultGammaCount
        h.lifecycle.fireWake()

        #expect(h.gamma.readDefaultGammaCount == baselineReadsBefore + 1)
        #expect(h.displayServices.storedBrightness == 1.0)
        #expect(h.controller.engagementState == .engaging)

        // Headroom returns after wake → active again.
        h.edrSignal.currentHeadroomValue = 2.0
        let reactivated = await waitUntil { h.controller.engagementState == .active }
        #expect(reactivated)
    }

    @Test("lifecycle events are ignored while XDR is off")
    func lifecycle_ignoredWhenDisabled() {
        let h = makeHarness()
        let restoresBefore = h.restoreColorSyncCount()
        h.lifecycle.fireScreensSleep()
        h.lifecycle.fireWake()
        h.lifecycle.fireDisplayParametersChanged()
        #expect(h.restoreColorSyncCount() == restoresBefore)
        #expect(h.controller.engagementState == .idle)
    }

    @Test("display parameter change restarts engagement")
    func lifecycle_displayChangeReengages() async {
        let h = makeHarness()
        _ = h.controller.enableXDR()
        h.edrSignal.currentHeadroomValue = 2.0
        let active = await waitUntil { h.controller.engagementState == .active }
        #expect(active)

        h.lifecycle.fireDisplayParametersChanged()
        // Headroom still granted → should settle back into active.
        let reactivated = await waitUntil { h.controller.engagementState == .active }
        #expect(reactivated)
    }
}
