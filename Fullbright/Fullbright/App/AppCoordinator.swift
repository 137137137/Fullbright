//
//  AppCoordinator.swift
//  Fullbright
//
//  Holds the app's dependency graph and reacts to auth-state transitions.
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
    private let authManager: any AuthenticationManaging
    let updaterController: SPUStandardUpdaterController
    let menuBarViewModel: MenuBarViewModel
    let settingsViewModel: SettingsViewModel

    private let keyManager: any BrightnessKeyManaging
    private let osdController: any OSDShowing
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

        // Key interception must track the XDR enabled state itself, not
        // just auth transitions — the menu-bar toggle flips XDR without
        // going through this coordinator, and stale interception swallows
        // brightness keys into a no-op (stuck OSD, dead keys).
        startObservingXDREnabled()

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
            // Immediate: the process is about to exit, there is no time
            // for the smooth disable fade.
            xdrController.disableXDR(immediate: true)
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
            // Don't auto-enable after an unclean shutdown — if XDR had a
            // hand in it (e.g. the macOS 27 beta display blackout), auto
            // enabling would re-trigger it on every login. The user can
            // still enable manually from the menu bar.
            if xdrController.previousSessionEndedDirty {
                logger.warning("Previous session ended dirty — skipping XDR auto-enable; waiting for manual toggle")
            } else {
                logger.info("Enabling XDR (supported=\(supported), canUse=\(canUse))")
                xdrController.enableXDR()
            }
        } else if enabled && !canUse {
            logger.info("Disabling XDR (canUse=\(canUse))")
            xdrController.disableXDR()
        }
        syncKeyInterception()
    }

    /// Single source of truth for brightness-key interception: swallow
    /// keys exactly while XDR is enabled (and auth allows it). Anything
    /// else means the native brightness controls must keep working.
    private func syncKeyInterception() {
        let shouldIntercept = xdrController.isEnabled && authManager.authState.canUseXDR
        guard keyManager.intercepting != shouldIntercept else { return }
        keyManager.intercepting = shouldIntercept
        if shouldIntercept {
            keyManager.start()
        } else {
            keyManager.stop()
        }
        logger.info("Brightness-key interception \(shouldIntercept ? "ON" : "OFF", privacy: .public)")
    }

    /// Re-syncs interception whenever `xdrController.isEnabled` changes,
    /// regardless of who changed it (menu toggle, gamma-conflict guard,
    /// auth transition).
    private func startObservingXDREnabled() {
        withObservationTracking {
            _ = xdrController.isEnabled
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.syncKeyInterception()
                self.startObservingXDREnabled()
            }
        }
    }
}
