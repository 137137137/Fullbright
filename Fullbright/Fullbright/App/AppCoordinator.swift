//
//  AppCoordinator.swift
//  Fullbright
//
//  Composition root: services, view models, auth-state → XDR wiring.
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
    private let restoreGammaIfNeeded: @Sendable () -> Void

    @ObservationIgnored
    private let authObservationTaskLock = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)

    init(xdrController: (any XDRControlling)? = nil,
         authManager: (any AuthenticationManaging)? = nil,
         keyManager: (any BrightnessKeyManaging)? = nil,
         restoreGammaIfNeeded: (@Sendable () -> Void)? = nil) {
        let xdr = xdrController ?? XDRController.shared
        let km = keyManager ?? BrightnessKeyManager.shared

        // Build the auth stack explicitly so the composition root owns the
        // singleton wiring (TLS pinning, default storage, etc.) rather than
        // letting AuthServerClient.init reach into singletons by itself.
        let auth: any AuthenticationManaging
        if let injected = authManager {
            auth = injected
        } else {
            let pinnedSession = CertificatePinningManager.shared.createPinnedURLSession()
            let serverClient = AuthServerClient(session: pinnedSession)
            auth = SecureAuthenticationManager(serverClient: serverClient)
        }

        let updater = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        self.xdrController = xdr
        self.authManager = auth
        self.keyManager = km
        self.osdController = XDRBrightnessOSDWindowController(xdrController: xdr)
        self.restoreGammaIfNeeded = restoreGammaIfNeeded ?? XDRController.restoreGammaIfNeeded
        self.updaterController = updater
        self.menuBarViewModel = MenuBarViewModel(xdrController: xdr, authManager: auth, updaterController: updater)
        self.settingsViewModel = SettingsViewModel(authManager: auth, updaterController: updater)

        // Auth manager kicks off its initial check + background monitoring here,
        // not from inside its own init (which would post a Task before init returns).
        auth.start()

        configureBrightnessKeyManager()
        syncXDRState()
        let observationTask = Self.createAuthObservationTask(coordinator: self)
        authObservationTaskLock.withLock { $0 = observationTask }
    }

    nonisolated deinit {
        authObservationTaskLock.withLock { $0?.cancel() }
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

    // MARK: - Brightness Key Manager Setup

    private func configureBrightnessKeyManager() {
        // Capture the step at wiring time so the C event-tap callback never has
        // to reach back into the manager singleton to read it.
        let step = keyManager.brightnessStep
        keyManager.onBrightnessKey = { [weak self] isUp in
            guard let self else { return }
            self.xdrController.adjustBrightness(delta: isUp ? step : -step)
            self.osdController.show()
        }
    }

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

    // MARK: - Auth State Observation

    /// Bridges `@Observable` auth state into a long-lived task that calls `syncXDRState()`
    /// on every distinct transition. This is the canonical pattern for observing
    /// `@Observable` properties imperatively (Apple docs / WWDC23 "Discover Observation").
    /// `withObservationTracking`'s `onChange` is edge-triggered (fires once per
    /// observation cycle), so this is not a polling loop.
    private static func createAuthObservationTask(coordinator: AppCoordinator) -> Task<Void, Never> {
        var lastState = coordinator.authManager.authState
        return Task { @MainActor [weak coordinator] in
            while !Task.isCancelled {
                guard let coordinator else { break }
                await withCheckedContinuation { continuation in
                    withObservationTracking {
                        _ = coordinator.authManager.authState
                    } onChange: {
                        continuation.resume()
                    }
                }
                guard !Task.isCancelled else { break }
                let newState = coordinator.authManager.authState
                if newState != lastState {
                    coordinator.syncXDRState()
                    lastState = newState
                }
            }
        }
    }
}
