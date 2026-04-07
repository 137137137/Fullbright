//
//  SecureAuthenticationManager.swift
//  Fullbright
//
//  Auth coordinator: trial, license, integrity monitoring, and state transitions.
//

import Foundation
import os

private let logger = Logger(subsystem: AppIdentifier.serviceID, category: "Auth")

@MainActor
@Observable
final class SecureAuthenticationManager: AuthenticationManaging {

    private(set) var authState: AuthenticationState = .notAuthenticated

    private let trialManager: any TrialManaging
    private let licenseManager: any LicenseManaging
    private let integrityChecker: any IntegrityChecking
    private let storage: any SecureStorageProviding
    private let deviceIdentifier: any DeviceIdentifying

    @ObservationIgnored
    private let integrityCheckTaskLock = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)

    nonisolated deinit {
        integrityCheckTaskLock.withLock { $0?.cancel() }
    }

    init(storage: (any SecureStorageProviding)? = nil,
         serverClient: (any AuthServerClientProviding)? = nil,
         keychain: (any KeychainProviding)? = nil,
         integrityChecker: (any IntegrityChecking)? = nil,
         deviceIdentifier: (any DeviceIdentifying)? = nil,
         trialManager: (any TrialManaging)? = nil,
         licenseManager: (any LicenseManaging)? = nil) {
        let resolvedStorage = storage ?? SecureFileStorage.shared
        let resolvedServerClient = serverClient ?? AuthServerClient(
            session: CertificatePinningManager.shared.createPinnedURLSession()
        )
        let resolvedKeychain = keychain ?? KeychainManager.shared
        let resolvedDeviceIdentifier = deviceIdentifier ?? DeviceIdentifier.shared

        self.storage = resolvedStorage
        self.integrityChecker = integrityChecker ?? IntegrityChecker.shared
        self.deviceIdentifier = resolvedDeviceIdentifier

        self.trialManager = trialManager ?? TrialManager(
            storage: resolvedStorage,
            serverClient: resolvedServerClient,
            keychain: resolvedKeychain,
            deviceIdentifier: resolvedDeviceIdentifier
        )

        self.licenseManager = licenseManager ?? LicenseManager(
            storage: resolvedStorage,
            serverClient: resolvedServerClient,
            deviceIdentifier: resolvedDeviceIdentifier
        )

        // Server responses route back through these callbacks.
        self.trialManager.setOnStateChange { [weak self] state in
            self?.authState = state
        }
        self.licenseManager.setOnStateChange { [weak self] state in
            guard let self else { return }
            self.authState = state
            if case .expired = state {
                // License revoked — fall back to trial if one is still valid
                self.authState = self.trialManager.checkTrialStatus()
            }
        }
    }

    // MARK: - Lifecycle

    /// Runs the initial check and starts monitoring. Kept out of `init` because
    /// the background Task captures `self` — posting before init returns is dicey.
    ///
    /// Async because `integrityChecker.passesAllChecks` offloads the blocking
    /// SecStaticCodeCheckValidity call to a detached task. Callers that can't
    /// await (e.g. AppCoordinator.init) wrap the call in `Task { await ... }`.
    func start() async {
        if await !integrityChecker.passesAllChecks() {
            authState = .expired
        } else {
            refreshAuthenticationState()
        }
        startIntegrityMonitoring()
    }

    // MARK: - Integrity Monitoring

    private func startIntegrityMonitoring() {
        let task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                guard !Task.isCancelled, let self else { return }
                if await !self.integrityChecker.passesAllChecks() {
                    self.authState = .expired
                }
                await self.validateCurrentState()
            }
        }
        integrityCheckTaskLock.withLock { $0 = task }
    }

    // MARK: - Authentication Status

    func refreshAuthenticationState() {
        if let licenseState = licenseManager.checkLicense() {
            authState = licenseState

            // Validate with server in background
            if case .authenticated(let licenseKey) = licenseState {
                licenseManager.validateLicenseInBackground(licenseKey: licenseKey)
            }
        } else {
            authState = trialManager.checkTrialStatus()
        }
    }

    // MARK: - Trial Management

    func startTrial() {
        authState = trialManager.startTrial()
    }

    // MARK: - License Management

    func activateLicense(licenseKey: String) async -> (success: Bool, message: String?) {
        let result = await licenseManager.activateLicense(licenseKey: licenseKey)
        if result.success {
            authState = .authenticated(licenseKey: licenseKey)
        }
        return result
    }

    // MARK: - State Validation

    private func validateCurrentState() async {
        switch authState {
        case .authenticated(let licenseKey):
            let result = await licenseManager.validateLicense(licenseKey: licenseKey)
            // Offline grace: `.offline` and `.valid` both stay authenticated.
            // Only an explicit `.invalid` (server revoked the license) expires it.
            if case .invalid = result {
                authState = .expired
            }
        case .trial:
            authState = trialManager.checkTrialStatus()
        case .notAuthenticated, .expired:
            break
        }
    }

    // MARK: - Cleanup

    func logout() {
        licenseManager.revokeLicense()
        authState = .expired
    }

    // MARK: - Developer Testing (DEBUG only)

    #if DEBUG
    func setTrialDaysRemaining(_ days: Int) {
        authState = trialManager.setTrialDaysRemaining(days)
        logger.debug("Trial set to \(days, privacy: .public) days remaining")
    }

    func resetTrial() {
        trialManager.resetTrial()
        licenseManager.revokeLicense()
        authState = .notAuthenticated
        refreshAuthenticationState()
        logger.debug("Trial reset - app will behave as first launch")
    }

    func expireTrial() {
        authState = trialManager.expireTrial()
        logger.debug("Trial expired")
    }

    func setValidLicense() {
        licenseManager.setValidLicense()
        authState = .authenticated(licenseKey: DebugConstants.testLicenseKey)
        logger.debug("Test license activated")
    }

    func printDebugInfo() {
        let deviceId = deviceIdentifier.secureIdentifier
        logger.debug("=== Authentication Debug Info ===")
        logger.debug("Current State: \(String(describing: self.authState), privacy: .public)")
        logger.debug("Device ID: \(deviceId)")
        logger.debug("\(self.trialManager.debugTrialInfo())")
        logger.debug("\(self.licenseManager.debugLicenseInfo())")
        logger.debug("================================")
    }
    #endif
}

// MARK: - DebugAuthManaging Conformance

#if DEBUG
extension SecureAuthenticationManager: DebugAuthManaging {}
#endif
