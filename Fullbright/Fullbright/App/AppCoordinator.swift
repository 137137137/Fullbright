//
//  AppCoordinator.swift
//  Fullbright
//
//  Holds the app's dependency graph and keeps XDR and the brightness keys
//  in step with the hardware.
//  Construction lives in AppComposition.makeDependencies() — this file
//  does NOT call `.init()` on any protocol-existential-typed field.
//

import Foundation
import Observation
import Sparkle
import os

private let logger = Logger(subsystem: AppIdentifier.serviceID, category: "Coordinator")

@MainActor
@Observable
final class AppCoordinator {
    private let xdrController: any XDRControlling
    let updaterController: SPUStandardUpdaterController
    let menuBarViewModel: MenuBarViewModel
    let settingsViewModel: SettingsViewModel

    private let keyManager: any BrightnessKeyManaging
    private let osdController: any OSDShowing
    private let restoreGammaIfNeeded: @MainActor () -> Void
    private let osdEventRouter: any OSDEventRouting
    let dockController: any DockVisibilityControlling

    init(dependencies: AppDependencies) {
        self.xdrController = dependencies.xdrController
        self.keyManager = dependencies.keyManager
        self.osdController = dependencies.osdController
        self.osdEventRouter = dependencies.osdEventRouter
        self.updaterController = dependencies.updaterController
        self.restoreGammaIfNeeded = dependencies.restoreGammaIfNeeded
        self.dockController = dependencies.dockController
        self.menuBarViewModel = dependencies.menuBarViewModel
        self.settingsViewModel = dependencies.settingsViewModel

        // Wire hardware input → XDR controller → OSD.
        osdEventRouter.attach(to: keyManager)

        syncXDRState()
    }

    nonisolated deinit {
        // OSDEventRouter leaves its callback in place intentionally — the
        // key manager is a long-lived singleton and recreating the callback
        // on next init is explicit.
    }

    // MARK: - App Lifecycle (called by AppDelegate)

    func restoreStateAfterCrash() {
        restoreGammaIfNeeded()
    }

    func prepareForTermination() {
        if xdrController.isEnabled {
            // Immediate: the process is about to exit, there is no time
            // for the smooth disable fade.
            xdrController.disableXDR(immediate: true)
            keyManager.intercepting = false
        }
    }

    // MARK: - XDR state sync

    private func syncXDRState() {
        let supported = xdrController.isXDRSupported
        let enabled = xdrController.isEnabled

        if supported && !enabled {
            // Don't auto-enable after an unclean shutdown — if XDR had a
            // hand in it (e.g. the macOS 27 beta display blackout), auto
            // enabling would re-trigger it on every login. The user can
            // still enable manually from the menu bar.
            if xdrController.previousSessionEndedDirty {
                logger.warning("Previous session ended dirty — skipping XDR auto-enable; waiting for manual toggle")
            } else {
                logger.info("Enabling XDR")
                xdrController.enableXDR()
            }
        }
        syncKeyInterception()
    }

    /// Single source of truth for brightness-key interception: swallow
    /// keys on XDR hardware — with XDR on, keys drive the unified pipeline;
    /// with XDR off they drive the backlight in SDR range through our OSD.
    /// Without XDR hardware the keys stay with macOS.
    private func syncKeyInterception() {
        let shouldIntercept = xdrController.isXDRSupported
        guard keyManager.intercepting != shouldIntercept else { return }
        keyManager.intercepting = shouldIntercept
        if shouldIntercept {
            keyManager.start()
        } else {
            keyManager.stop()
        }
        logger.info("Brightness-key interception \(shouldIntercept ? "ON" : "OFF", privacy: .public)")
    }
}
