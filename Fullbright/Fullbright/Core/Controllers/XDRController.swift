//
//  XDRController.swift
//  Fullbright
//
//  XDR brightness orchestrator.
//  Delegates to DisplayServicesClient, NightShiftManager,
//  GammaTableManager, HDRWindow, and drives the EDR engagement
//  state machine.
//
//  Enable flow:
//    1. Snapshot pre-XDR brightness (perceptual + linear).
//    2. Disable Night Shift, restore ColorSync, re-capture gamma baseline.
//    3. Apply a compensating gamma scale ≈ current linear brightness, THEN
//       drive the backlight to max — perceived brightness stays put
//       instead of flashing to full.
//    4. Disable ambient light compensation.
//    5. Create the HDR trigger window (EDR headroom allocation).
//    6. Poll EDR headroom until the OS grants it (macOS 26+ can refuse for
//       ~30s after lid-open/wake), then fade gamma up smoothly. On timeout,
//       cool down and retry. While active, monitor headroom and re-fade on
//       changes; clamp back to SDR if headroom is revoked.
//
//  Disable flow:
//    1. Stop engagement + gamma activity (fades, integrity monitor)
//    2. CGDisplayRestoreColorSyncSettings()
//    3. Restore Night Shift (only if it was enabled before)
//    4. Re-enable ambient light compensation, restore saved brightness
//    5. Destroy HDR window
//

import Foundation
import AppKit
import CoreGraphics
import os

private let logger = Logger(subsystem: AppIdentifier.serviceID, category: "XDR")

// MARK: - Timing

/// All intervals used by the EDR engagement state machine, injectable so
/// tests can run the machine in milliseconds.
struct XDRTiming: Sendable {
    /// Interval between EDR headroom polls while waiting for the OS grant.
    var engagePollInterval: Duration = .milliseconds(100)
    /// How long to wait for the grant before entering cooldown.
    var engageTimeout: Duration = .seconds(25)
    /// Cooldown before re-requesting after a timeout. macOS refuses grants
    /// made too eagerly after lid-open/wake; retrying sooner keeps it locked.
    var retryCooldown: Duration = .seconds(30)
    /// Interval between headroom checks while XDR is active.
    var monitorInterval: Duration = .milliseconds(500)
    /// Gamma fade duration for enable/headroom-change transitions.
    var brightnessFadeDuration: TimeInterval = 0.35
    /// Gamma fade duration for brightness-key steps (kept short so keys
    /// feel immediate).
    var keyFadeDuration: TimeInterval = 0.15

    static let production = XDRTiming()
}

// MARK: - XDRController

@MainActor
@Observable
final class XDRController: XDRControlling {

    // MARK: - Constants

    private enum XDRThreshold {
        /// Minimum potential EDR value to consider display XDR-capable
        static let minimumEDR: Double = 1.5
        /// Granted headroom above this means EDR is engaged and gamma may
        /// scale past 1.0.
        static let edrReady: Double = 1.05
        /// Headroom change worth recomputing the brightness ceiling for.
        static let headroomEpsilon: Double = 0.0001
    }

    private enum BrightnessThreshold {
        /// Minimum brightness to consider a valid pre-XDR reading
        static let minimumRestore: Float = 0.02
        /// Default brightness to restore if pre-XDR reading was too low
        static let defaultRestore: Float = 0.8
    }

    /// EDR engagement phase. `.active` is the only state in which gamma
    /// may scale above 1.0.
    enum EDREngagementState: Equatable {
        case idle
        case engaging
        case cooldown
        case active
    }

    // MARK: - Observable State

    private(set) var isEnabled: Bool = false
    /// Unified brightness: 0.0 = screen min (~1 nit), 0.5 = SDR max (~500 nits), 1.0 = XDR max (~1600 nits)
    private(set) var brightness: Float = 0.5
    /// Current nits (computed from brightness)
    private(set) var currentNits: Int = 500
    private(set) var engagementState: EDREngagementState = .idle

    // MARK: - Dependencies

    private let displayID: UInt32
    private let displayServices: any DisplayServicesProviding
    private let nightShiftManager: any NightShiftManaging
    private var gammaManager: any GammaTableManaging
    private let displayConfigurator: any DisplayConfiguring
    private let dirtyFlagStore: any XDRDirtyFlagStoring
    private let edrSignal: any EDRSignalProviding
    private let lifecycleObserver: any DisplayLifecycleObserving
    private let timing: XDRTiming
    private let restoreColorSync: @MainActor () -> Void

    // State
    private var hdrWindow: NSWindow?
    private var nightShiftWasEnabled = false
    private var brightnessBeforeXDR: Float = 0.8
    /// Linear luminance fraction at enable time; the disable fade lands
    /// here before the backlight is restored.
    private var luminanceBeforeXDR: Float = 0.8
    /// Set on the first successful engage after enableXDR so re-engages
    /// (wake, headroom loss) don't re-jump the user's brightness to peak.
    private var hasReachedPeakThisEnable = false
    /// Set when the user adjusts brightness before the first engage
    /// completes — their choice wins over the jump-to-peak default.
    private var hasUserAdjustedSinceEnable = false
    private var lastObservedHeadroom: Double = 1.0

    /// The engagement task spawned by enableXDR. Wrapped in a lock so the
    /// `nonisolated deinit` can cancel it even though the controller is
    /// MainActor-isolated. Without this, releasing the singleton (e.g. in
    /// tests) leaks a running Task until its next sleep tick.
    @ObservationIgnored
    private let engageTaskLock = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)

    /// Pending smooth-disable teardown. If the app dies mid-fade, the
    /// dirty flag (cleared only in completeTeardown) restores gamma on
    /// next launch.
    @ObservationIgnored
    private let teardownTaskLock = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)

    nonisolated deinit {
        engageTaskLock.withLock { $0?.cancel() }
        teardownTaskLock.withLock { $0?.cancel() }
    }

    private let supported: Bool

    init(displayID: UInt32 = CGMainDisplayID(),
         displayServices: any DisplayServicesProviding,
         nightShiftManager: any NightShiftManaging,
         gammaManager: any GammaTableManaging,
         displayConfigurator: any DisplayConfiguring,
         dirtyFlagStore: any XDRDirtyFlagStoring,
         edrSignal: any EDRSignalProviding,
         lifecycleObserver: any DisplayLifecycleObserving,
         timing: XDRTiming = .production,
         restoreColorSync: @escaping @MainActor () -> Void = { CGDisplayRestoreColorSyncSettings() },
         supportsXDROverride: Bool? = nil) {
        self.displayID = displayID
        self.displayServices = displayServices
        self.nightShiftManager = nightShiftManager
        self.gammaManager = gammaManager
        self.displayConfigurator = displayConfigurator
        self.dirtyFlagStore = dirtyFlagStore
        self.edrSignal = edrSignal
        self.lifecycleObserver = lifecycleObserver
        self.timing = timing
        self.restoreColorSync = restoreColorSync

        if let override = supportsXDROverride {
            supported = override
        } else {
            supported = edrSignal.potentialHeadroom(displayID: displayID) > XDRThreshold.minimumEDR
        }

        // Read the default gamma table at init before anything modifies it.
        self.gammaManager.readDefaultGamma(displayID: self.displayID)

        // Configure the display for XDR capability. Skipped when the override
        // is explicitly provided to keep tests off the real SkyLight path.
        if supported && supportsXDROverride == nil {
            self.displayConfigurator.configureForXDR(displayID: self.displayID)
        }

        // If gamma writes repeatedly fail to stick (another gamma app, or
        // a broken CGSetDisplayTransferByTable), fall back to a safe state
        // rather than fighting forever.
        self.gammaManager.onPersistentGammaConflict = { [weak self] in
            guard let self, self.isEnabled else { return }
            logger.error("Persistent gamma conflict — disabling XDR")
            // Immediate: gamma writes aren't sticking, so fading is moot.
            self.disableXDR(immediate: true)
            NotificationCenter.default.post(name: .fullbrightGammaConflict, object: nil)
        }

        lifecycleObserver.onScreensSleep = { [weak self] in self?.handleScreensSleep() }
        lifecycleObserver.onWake = { [weak self] in self?.handleWake() }
        lifecycleObserver.onDisplayParametersChanged = { [weak self] in self?.handleDisplayParametersChanged() }
        lifecycleObserver.start()
    }

    // MARK: - Public API

    var isXDRSupported: Bool { supported }

    @discardableResult
    func enableXDR() -> Bool {
        guard supported, !isEnabled else { return supported && isEnabled }

        // A smooth disable may still be mid-fade; finish it now so the
        // enable sequence starts from a fully restored display.
        if let pending = teardownTaskLock.withLock({ task -> Task<Void, Never>? in
            defer { task = nil }
            return task
        }) {
            pending.cancel()
            completeTeardown()
        }

        brightnessBeforeXDR = displayServices.getBrightness(displayID)

        // Luminance fraction the user currently sees, used to hold
        // perceived brightness steady across the backlight jump. Falls
        // back to a gamma-2 approximation of the perceptual slider value
        // when the linear symbol is unavailable.
        let linear = displayServices.getLinearBrightness(displayID)
        let luminanceFraction = linear ?? (brightnessBeforeXDR * brightnessBeforeXDR)
        luminanceBeforeXDR = luminanceFraction
        let softwareFloor = gammaManager.softwareBrightness(from: 0.0)
        let compensation = min(1.0, max(softwareFloor, luminanceFraction))

        // Disable Night Shift before capturing the gamma baseline so its
        // tint doesn't get baked into the table we scale from.
        nightShiftWasEnabled = nightShiftManager.isEnabled
        nightShiftManager.setEnabled(false)

        // Clear active gamma modifications, then capture a fresh baseline
        // (the init-time capture may predate profile/Night Shift changes).
        restoreColorSync()
        gammaManager.readDefaultGamma(displayID: displayID)

        // Flash guard: dim via gamma by the same fraction the backlight
        // jump adds, in adjacent statements so the mismatch lasts a frame.
        gammaManager.applyScaledGamma(displayID: displayID, softwareBrightness: compensation)
        if !displayServices.setBrightness(displayID, 1.0) {
            logger.warning("DisplayServices.setBrightness returned failure during XDR enable")
        }
        if !displayServices.setLinearBrightness(displayID, 1.0) {
            logger.warning("DisplayServices.setLinearBrightness returned failure during XDR enable")
        }

        if !displayServices.setAmbientLightCompensation(displayID, enabled: false) {
            logger.warning("DisplayServices.setAmbientLightCompensation(false) returned failure")
        }

        // Reflect the held perceived level in unified brightness so keys
        // and the OSD start from where the screen actually is.
        brightness = unifiedBrightness(forSoftwareBrightness: compensation)

        // Create HDR window (triggers EDR headroom allocation)
        if let screen = NSScreen.main {
            hdrWindow = HDRWindowFactory.makeWindow(for: screen)
        }

        isEnabled = true
        hasReachedPeakThisEnable = false
        hasUserAdjustedSinceEnable = false
        dirtyFlagStore.isDirty = true
        updateNits()

        startEngagement()
        return true
    }

    @discardableResult
    func disableXDR(immediate: Bool) -> Bool {
        guard isEnabled else { return false }

        stopEngagement()
        isEnabled = false

        let fadeDuration = timing.brightnessFadeDuration
        if immediate || fadeDuration <= 0 {
            completeTeardown()
            return true
        }

        // Ease the boosted gamma back to the pre-XDR luminance before
        // yanking ColorSync and the backlight — the mirror of the enable
        // flash guard. The dirty flag stays set until teardown completes,
        // so a crash mid-fade still restores on next launch.
        let softwareFloor = gammaManager.softwareBrightness(from: 0.0)
        let landing = min(1.0, max(softwareFloor, luminanceBeforeXDR))
        gammaManager.fadeToSoftwareBrightness(landing, displayID: displayID, duration: fadeDuration)

        let task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(fadeDuration) + .milliseconds(50))
            guard !Task.isCancelled, let self else { return }
            self.teardownTaskLock.withLock { $0 = nil }
            self.completeTeardown()
        }
        teardownTaskLock.withLock { existing in
            existing?.cancel()
            existing = task
        }
        return true
    }

    /// The synchronous tail of disable: restore ColorSync/Night Shift/ALC/
    /// backlight, drop the HDR window, clear the dirty flag.
    private func completeTeardown() {
        gammaManager.stopGammaActivity()

        // Step 1: Restore gamma
        restoreColorSync()

        // Step 2: Restore Night Shift only if it was on before
        if nightShiftWasEnabled {
            nightShiftManager.setEnabled(true)
        }

        // Step 3: Re-enable adaptive brightness
        if !displayServices.setAmbientLightCompensation(displayID, enabled: true) {
            logger.warning("DisplayServices.setAmbientLightCompensation(true) returned failure")
        }

        // Step 4: Restore brightness
        let restore = brightnessBeforeXDR > BrightnessThreshold.minimumRestore ? brightnessBeforeXDR : BrightnessThreshold.defaultRestore
        if !displayServices.setBrightness(displayID, restore) {
            logger.warning("DisplayServices.setBrightness returned failure during XDR disable")
        }

        // Step 5: Destroy HDR window
        hdrWindow?.orderOut(nil)
        hdrWindow = nil

        gammaManager.resetLogging()
        dirtyFlagStore.isDirty = false
    }

    /// Adjust unified brightness. Called from brightness key handler.
    func adjustBrightness(delta: Float) {
        guard isEnabled else { return }
        hasUserAdjustedSinceEnable = true
        brightness = max(0.0, min(1.0, brightness + delta))
        updateNits()
        fadeToCurrentTarget(duration: timing.keyFadeDuration)
    }

    // MARK: - Display Lifecycle

    private func handleScreensSleep() {
        guard isEnabled else { return }
        logger.info("Screens sleeping — restoring gamma so no boosted table survives sleep")
        stopEngagement()
        gammaManager.stopGammaActivity()
        restoreColorSync()
        engagementState = .engaging
    }

    private func handleWake() {
        guard isEnabled else { return }
        logger.info("Woke from sleep — re-running XDR engage sequence")
        restoreColorSync()
        gammaManager.readDefaultGamma(displayID: displayID)

        // Reassert the state the OS may have rolled back during sleep.
        let clampedTarget = min(1.0, gammaManager.softwareBrightness(from: brightness))
        gammaManager.applyScaledGamma(displayID: displayID, softwareBrightness: clampedTarget)
        if !displayServices.setBrightness(displayID, 1.0) {
            logger.warning("DisplayServices.setBrightness returned failure during wake re-assert")
        }
        if !displayServices.setLinearBrightness(displayID, 1.0) {
            logger.warning("DisplayServices.setLinearBrightness returned failure during wake re-assert")
        }
        if !displayServices.setAmbientLightCompensation(displayID, enabled: false) {
            logger.warning("DisplayServices.setAmbientLightCompensation(false) returned failure during wake re-assert")
        }

        startEngagement()
    }

    private func handleDisplayParametersChanged() {
        guard isEnabled else { return }
        logger.info("Display parameters changed — re-syncing XDR state")
        startEngagement()
    }

    // MARK: - EDR Engagement

    private func startEngagement() {
        engagementState = .engaging
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runEngagementLoop()
        }
        engageTaskLock.withLock { existing in
            existing?.cancel()
            existing = task
        }
    }

    private func stopEngagement() {
        engageTaskLock.withLock { existing in
            existing?.cancel()
            existing = nil
        }
        engagementState = .idle
    }

    private func runEngagementLoop() async {
        while !Task.isCancelled && isEnabled {
            engagementState = .engaging
            let engaged = await pollUntilEngaged()
            guard !Task.isCancelled, isEnabled else { return }

            if !engaged {
                engagementState = .cooldown
                logger.warning("EDR headroom not granted within timeout — cooling down before retry")
                try? await Task.sleep(for: timing.retryCooldown)
                continue
            }

            engagementState = .active
            refreshHeadroom()

            // Land at full XDR on first engage — the user asked for XDR by
            // toggling it on. Skipped if they already adjusted brightness.
            if !hasReachedPeakThisEnable && !hasUserAdjustedSinceEnable {
                brightness = 1.0
                updateNits()
            }
            hasReachedPeakThisEnable = true

            fadeToCurrentTarget(duration: timing.brightnessFadeDuration)
            gammaManager.startIntegrityMonitoring(displayID: displayID)

            await monitorHeadroom()
        }
    }

    /// Polls until the OS grants EDR headroom. Returns false on timeout.
    private func pollUntilEngaged() async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timing.engageTimeout
        while !Task.isCancelled && isEnabled {
            if edrSignal.currentHeadroom(displayID: displayID) > XDRThreshold.edrReady {
                return true
            }
            if clock.now >= deadline { return false }
            try? await Task.sleep(for: timing.engagePollInterval)
        }
        return false
    }

    /// Watches granted headroom while active: re-fades on changes, drops
    /// back to the engage phase (with gamma clamped to SDR) on revocation.
    private func monitorHeadroom() async {
        lastObservedHeadroom = edrSignal.currentHeadroom(displayID: displayID)
        while !Task.isCancelled && isEnabled {
            try? await Task.sleep(for: timing.monitorInterval)
            guard !Task.isCancelled, isEnabled else { return }

            let headroom = edrSignal.currentHeadroom(displayID: displayID)
            if headroom <= XDRThreshold.edrReady {
                logger.warning("EDR headroom revoked (\(headroom, privacy: .public)) — clamping to SDR and re-engaging")
                engagementState = .engaging
                fadeToCurrentTarget(duration: timing.brightnessFadeDuration)
                return
            }
            if abs(headroom - lastObservedHeadroom) > XDRThreshold.headroomEpsilon {
                lastObservedHeadroom = headroom
                refreshHeadroom()
                updateNits()
                fadeToCurrentTarget(duration: timing.brightnessFadeDuration)
            }
        }
    }

    // MARK: - Private

    private func refreshHeadroom() {
        gammaManager.updateEDRHeadroom(
            current: edrSignal.currentHeadroom(displayID: displayID),
            potential: edrSignal.potentialHeadroom(displayID: displayID)
        )
        updateNits()
    }

    /// Fades gamma toward the current unified-brightness target, clamped
    /// to SDR (scale ≤ 1.0) unless EDR headroom is actively granted —
    /// values above 1.0 without headroom just clip to white.
    private func fadeToCurrentTarget(duration: TimeInterval) {
        var target = gammaManager.softwareBrightness(from: brightness)
        if engagementState != .active {
            target = min(target, 1.0)
        }
        gammaManager.fadeToSoftwareBrightness(target, displayID: displayID, duration: duration)
    }

    /// Inverse of the SDR branch of `softwareBrightness(from:)`.
    private func unifiedBrightness(forSoftwareBrightness scale: Float) -> Float {
        let floor = gammaManager.softwareBrightness(from: 0.0)
        guard floor < 1.0 else { return BrightnessNitsConverter.sdrXDRBoundary }
        let t = (min(1.0, max(floor, scale)) - floor) / (1.0 - floor)
        return t * BrightnessNitsConverter.sdrXDRBoundary
    }

    private func updateNits() {
        currentNits = BrightnessNitsConverter.nits(from: brightness, maxNits: gammaManager.displayPeakNits)
    }
}
