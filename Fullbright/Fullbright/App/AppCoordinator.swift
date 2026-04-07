//
//  AppCoordinator.swift
//  Fullbright
//
//  Holds the app's dependency graph and reacts to auth-state transitions.
//  Construction lives in AppComposition.makeDependencies() — this file
//  does NOT call `.init()` on any protocol-existential-typed field.
//

import Foundation
import Sparkle
import os

private let logger = Logger(subsystem: AppIdentifier.serviceID, category: "Coordinator")

@MainActor
@Observable
final class AppCoordinator {
    private let xdrController: any XDRControlling
    private let authManager: any AuthenticationManaging
    let updaterController: SPUStandardUpdaterController
    let menuBarViewModel: MenuBarViewModel
    let settingsViewModel: SettingsViewModel

    private let keyManager: any BrightnessKeyManaging
    private let osdController: XDRBrightnessOSDWindowController
    private let restoreGammaIfNeeded: @MainActor () -> Void
    private let authStateObserver: any AuthStateObserving
    private let osdEventRouter: any OSDEventRouting
    let dockController: any DockVisibilityControlling

    init(dependencies: AppDependencies) {
        self.xdrController = dependencies.xdrController
        self.keyManager = dependencies.keyManager
        self.authManager = dependencies.authManager
        self.osdController = dependencies.osdController
        self.authStateObserver = dependencies.authStateObserver
        self.osdEventRouter = dependencies.osdEventRouter
        self.updaterController = dependencies.updaterController
        self.restoreGammaIfNeeded = dependencies.restoreGammaIfNeeded
        self.dockController = dependencies.dockController
        self.menuBarViewModel = dependencies.menuBarViewModel
        self.settingsViewModel = dependencies.settingsViewModel

        // Wire hardware input → XDR controller → OSD. This doesn't depend
        // on auth state so it can happen first.
        osdEventRouter.attach(to: keyManager)

        // Initial XDR sync reflects the starting authState (typically
        // .notAuthenticated on first launch). Subsequent transitions
        // are driven by the observer below.
        syncXDRState()

        // Kick off the initial auth check and start the observer in a
        // single Task. We await the observer's handshake so any auth
        // state mutations downstream of auth.start() are guaranteed to
        // fire transition callbacks.
        let authManager = self.authManager
        let authStateObserver = self.authStateObserver
        Task { @MainActor [weak self] in
            await authStateObserver.start { [weak self] _ in
                self?.syncXDRState()
            }
            await authManager.start()
        }
    }

    nonisolated deinit {
        // AuthStateObserver's own deinit cancels its task; nothing else to
        // clean up here. OSDEventRouter leaves its callback in place
        // intentionally — the key manager is a long-lived singleton and
        // recreating the callback on next init is explicit.
    }

    // MARK: - App Lifecycle (called by AppDelegate)

    func restoreStateAfterCrash() {
        restoreGammaIfNeeded()
    }

    func prepareForTermination() {
        if xdrController.isEnabled {
            xdrController.disableXDR()
            keyManager.intercepting = false
        }
    }

    func handleOnboardingCompleted() {
        if authManager.authState == .notAuthenticated {
            authManager.startTrial()
        }
    }

    // MARK: - XDR state sync

    private func syncXDRState() {
        let supported = xdrController.isXDRSupported
        let canUse = authManager.authState.canUseXDR
        let enabled = xdrController.isEnabled

        if supported && canUse && !enabled {
            logger.info("Enabling XDR (supported=\(supported), canUse=\(canUse))")
            xdrController.enableXDR()
            keyManager.intercepting = true
            keyManager.start()
        } else if enabled && !canUse {
            logger.info("Disabling XDR (canUse=\(canUse))")
            xdrController.disableXDR()
            keyManager.intercepting = false
            keyManager.stop()
        } else if !canUse {
            keyManager.intercepting = false
            keyManager.stop()
        }
    }
}
