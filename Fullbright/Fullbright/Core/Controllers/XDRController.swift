//
//  XDRController.swift
//  Fullbright
//
//  XDR brightness orchestrator.
//  Delegates to DisplayServicesClient, NightShiftManager,
//  GammaTableManager, HDRWindow.
//
//  Enable flow:
//    1. DisplayServicesSetBrightness(displayID, 1.0)
//    2. DisplayServicesSetLinearBrightness(displayID, 1.0)
//    3. DisplayServicesEnableAmbientLightCompensation(displayID, false)
//    4. [CBBlueLightClient setEnabled:NO]
//    5. HDRWindow (Branch B — triggers EDR headroom allocation)
//    6. After 2s: scale default gamma table, reapply continuously at 60 Hz
//
//  Disable flow:
//    1. Stop gamma reapply
//    2. CGDisplayRestoreColorSyncSettings()
//    3. Restore Night Shift (only if was enabled before)
//    4. DisplayServicesEnableAmbientLightCompensation(displayID, true)
//    5. DisplayServicesSetBrightness(displayID, savedBrightness)
//    6. Destroy HDRWindow
//

import Foundation
import AppKit
import CoreGraphics
import os

private let skyLightPath = "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight"

private let logger = Logger(subsystem: AppIdentifier.serviceID, category: "XDR")

// MARK: - XDRController

@MainActor
@Observable
final class XDRController: XDRControlling {
    static let shared = XDRController()

    // MARK: - Constants

    private enum Timing {
        /// Delay before gamma ramp-up after XDR enable (EDR headroom allocation time)
        static let gammaRampDelay: TimeInterval = 2.0
    }

    private enum XDRThreshold {
        /// Minimum EDR value to consider display XDR-capable
        static let minimumEDR: Double = 1.5
    }

    private enum BrightnessThreshold {
        /// Minimum brightness to consider a valid pre-XDR reading
        static let minimumRestore: Float = 0.02
        /// Default brightness to restore if pre-XDR reading was too low
        static let defaultRestore: Float = 0.8
        /// Multiplier to convert hardware brightness to unified brightness at XDR enable
        static let initialScaling: Float = 0.5
    }

    private enum SLSMode {
        /// SLSConfigureDisplayEnabled mode values
        static let configModes: [UInt32] = [4, 3, 5, 2]
    }

    // MARK: - Dirty Gamma Flag (crash recovery)

    /// Called on launch — if the app crashed with modified gamma, restore system defaults.
    nonisolated static func restoreGammaIfNeeded() {
        if UserDefaults.standard.bool(forKey: DefaultsKey.gammaModified) {
            logger.warning("Dirty gamma flag found — restoring ColorSync settings from previous crash")
            CGDisplayRestoreColorSyncSettings()
            clearDirtyGammaFlag()
        }
    }

    private nonisolated static func setDirtyGammaFlag() {
        UserDefaults.standard.set(true, forKey: DefaultsKey.gammaModified)
    }

    nonisolated static func clearDirtyGammaFlag() {
        UserDefaults.standard.set(false, forKey: DefaultsKey.gammaModified)
    }

    // MARK: - Observable State

    private(set) var isEnabled: Bool = false
    /// Unified brightness: 0.0 = screen min (~1 nit), 0.5 = SDR max (~500 nits), 1.0 = XDR max (~1600 nits)
    private(set) var brightness: Float = 0.5
    /// Current nits (computed from brightness)
    private(set) var currentNits: Int = 500

    // MARK: - Dependencies

    private let displayID: UInt32
    private let displayServices: any DisplayServicesProviding
    private let nightShiftManager: any NightShiftManaging
    private var gammaManager: any GammaTableManaging

    // State
    private var hdrWindow: NSWindow?
    private var nightShiftWasEnabled = false
    private var brightnessBeforeXDR: Float = 0.8

    /// The ramp-up delay task spawned by enableXDR. Wrapped in a lock so the
    /// `nonisolated deinit` can cancel it even though the controller is
    /// MainActor-isolated. Without this, releasing the singleton (e.g. in
    /// tests) leaks a running Task until it finishes its sleep.
    @ObservationIgnored
    private let rampTaskLock = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)

    nonisolated deinit {
        rampTaskLock.withLock { $0?.cancel() }
    }

    private let supported: Bool

    init(displayID: UInt32 = CGMainDisplayID(),
         displayServices: (any DisplayServicesProviding)? = nil,
         nightShiftManager: (any NightShiftManaging)? = nil,
         gammaManager: (any GammaTableManaging)? = nil,
         supportsXDROverride: Bool? = nil) {
        self.displayID = displayID
        self.displayServices = displayServices ?? DisplayServicesClient()
        self.nightShiftManager = nightShiftManager ?? NightShiftManager()
        self.gammaManager = gammaManager ?? GammaTableManager()

        if let override = supportsXDROverride {
            supported = override
        } else if let screen = NSScreen.main {
            supported = screen.maximumPotentialExtendedDynamicRangeColorComponentValue > XDRThreshold.minimumEDR
        } else {
            supported = false
        }

        // Read the default gamma table at init before anything modifies it.
        self.gammaManager.readDefaultGamma(displayID: self.displayID)

        // Configure the display for XDR capability. Skipped when the override
        // is explicitly provided to keep tests off the real SkyLight path.
        if supported && supportsXDROverride == nil {
            Self.configureDisplayForXDR(self.displayID)
        }
    }

    /// SLSConfigureDisplayEnabled -> CGCompleteDisplayConfiguration
    private static func configureDisplayForXDR(_ displayID: UInt32) {
        typealias SLSConfigFn = @convention(c) (OpaquePointer, UInt32, UInt32) -> Int32

        guard let slHandle = PrivateFrameworkLoader.loadFramework(skyLightPath),
              let slsConfigure: SLSConfigFn = PrivateFrameworkLoader.symbol(
                  "SLSConfigureDisplayEnabled", from: slHandle, as: SLSConfigFn.self
              ) else { return }

        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let cfg = config else { return }

        for mode in SLSMode.configModes {
            _ = slsConfigure(cfg, mode, 1)
        }

        _ = CGCompleteDisplayConfiguration(cfg, .permanently)
    }

    // MARK: - Public API

    var isXDRSupported: Bool { supported }

    @discardableResult
    func enableXDR() -> Bool {
        guard supported else { return false }

        brightnessBeforeXDR = displayServices.getBrightness(displayID)

        // Step 1-2: Set brightness and linear brightness to max
        displayServices.setBrightness(displayID, 1.0)
        displayServices.setLinearBrightness(displayID, 1.0)

        // Step 3: Disable adaptive brightness
        displayServices.setAmbientLightCompensation(displayID, enabled: false)

        // Step 4: Disable Night Shift (must happen before gamma reads)
        nightShiftWasEnabled = nightShiftManager.isEnabled
        nightShiftManager.setEnabled(false)

        // Step 5: Restore ColorSync to clear active gamma modifications
        CGDisplayRestoreColorSyncSettings()

        // Step 6: Create HDR window (triggers EDR headroom allocation)
        if let screen = NSScreen.main {
            hdrWindow = HDRWindowFactory.makeWindow(for: screen)
        }

        isEnabled = true
        Self.setDirtyGammaFlag()

        // Step 7: After 2s, apply scaled gamma table
        let task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Timing.gammaRampDelay))
            guard !Task.isCancelled, let self, self.isEnabled else { return }
            self.rampUpGamma()
        }
        rampTaskLock.withLock { existing in
            existing?.cancel()
            existing = task
        }

        return true
    }

    @discardableResult
    func disableXDR() -> Bool {
        guard isEnabled else { return false }

        // Stop gamma reapply
        rampTaskLock.withLock { existing in
            existing?.cancel()
            existing = nil
        }
        gammaManager.stopRenderLoop()

        // Step 1: Restore gamma
        CGDisplayRestoreColorSyncSettings()

        // Step 2: Restore Night Shift only if it was on before
        if nightShiftWasEnabled {
            nightShiftManager.setEnabled(true)
        }

        // Step 3: Re-enable adaptive brightness
        displayServices.setAmbientLightCompensation(displayID, enabled: true)

        // Step 4: Restore brightness
        let restore = brightnessBeforeXDR > BrightnessThreshold.minimumRestore ? brightnessBeforeXDR : BrightnessThreshold.defaultRestore
        displayServices.setBrightness(displayID, restore)

        // Step 5: Destroy HDR window
        hdrWindow?.orderOut(nil)
        hdrWindow = nil

        isEnabled = false
        gammaManager.resetLogging()
        Self.clearDirtyGammaFlag()
        return true
    }

    /// Adjust unified brightness. Called from brightness key handler.
    func adjustBrightness(delta: Float) {
        guard isEnabled else { return }
        brightness = max(0.0, min(1.0, brightness + delta))
        updateNits()
        gammaManager.updateBrightness(from: brightness)
    }

    // MARK: - Private

    private func rampUpGamma() {
        guard isEnabled else { return }

        gammaManager.recomputeMaxEDR()

        // Initialize unified brightness from hardware state before XDR enable
        brightness = brightnessBeforeXDR * BrightnessThreshold.initialScaling
        updateNits()
        let initialTarget = gammaManager.softwareBrightness(from: brightness)

        // Apply immediately and start 60 Hz reapply with smooth lerp
        gammaManager.startSmoothTransition(to: initialTarget, displayID: displayID)
    }

    private func updateNits() {
        currentNits = BrightnessNitsConverter.nits(from: brightness, maxEDR: gammaManager.maxEDR)
    }
}
