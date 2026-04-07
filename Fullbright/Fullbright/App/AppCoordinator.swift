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

    init(dependencies: AppDependencies) {
        self.xdrController = dependencies.xdrController
        self.keyManager = dependencies.keyManager
        self.authManager = dependencies.authManager
        self.osdController = dependencies.osdController
        self.authStateObserver = dependencies.authStateObserver
        self.osdEventRouter = dependencies.osdEventRouter
        self.updaterController = dependencies.updaterController
        self.restoreGammaIfNeeded = dependencies.restoreGammaIfNeeded
        self.menuBarViewModel = dependencies.menuBarViewModel
        self.settingsViewModel = dependencies.settingsViewModel

        // Kick off the initial auth check. Deferred out of
        // SecureAuthenticationManager.init so the background Task it
        // posts doesn't capture a half-initialized self.
        Task { @MainActor in
            await self.authManager.start()
        }

        // Wire hardware input → XDR controller → OSD.
        osdEventRouter.attach(to: keyManager)

        // React to auth-state transitions and re-sync XDR + key manager.
        syncXDRState()
        authStateObserver.start { [weak self] _ in
            self?.syncXDRState()
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
