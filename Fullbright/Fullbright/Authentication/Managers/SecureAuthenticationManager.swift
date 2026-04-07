//
//  SecureAuthenticationManager.swift
//  Fullbright
//
//  Slim auth coordinator. Composes trial + license managers, delegates
//  state transitions to the pure AuthStateReducer, and delegates the
//  integrity-monitoring loop to IntegrityMonitor. All logic that can be
//  tested without I/O lives in the reducer; all logic that needs a Task
//  lives in the monitor.
//

import Foundation
import os

private let logger = Logger(subsystem: AppIdentifier.serviceID, category: "Auth")

@MainActor
@Observable
final class SecureAuthenticationManager: AuthenticationManaging {

    // Internal (default) so the DEBUG extension in
    // SecureAuthenticationManager+Debug.swift can mutate state. Only
    // accessed from within this module.
    var authState: AuthenticationState = .notAuthenticated

    // `internal` (rather than `private`) so the DEBUG extension in
    // SecureAuthenticationManager+Debug.swift can reach them directly. The
    // DEBUG extension lives in the same module and file-private would force
    // everything into a single file. In production these are read-only.
    let trialManager: any TrialManaging
    let licenseManager: any LicenseManaging
    private let integrityChecker: any IntegrityChecking
    private let integrityMonitor: any IntegrityMonitoring

    #if DEBUG
    // Only used by `printDebugInfo`; not wired to any production logic.
    let deviceIdentifier: any DeviceIdentifying
    #endif

    // Interval between background integrity + state re-validation ticks.
    private static let monitoringInterval: Duration = .seconds(300)

    init(storage: (any SecureStorageProviding)? = nil,
         serverClient: (any AuthServerClientProviding)? = nil,
         keychain: (any KeychainProviding)? = nil,
         integrityChecker: (any IntegrityChecking)? = nil,
         integrityMonitor: (any IntegrityMonitoring)? = nil,
         deviceIdentifier: (any DeviceIdentifying)? = nil,
         trialManager: (any TrialManaging)? = nil,
         licenseManager: (any LicenseManaging)? = nil) {
        let resolvedStorage = storage ?? SecureFileStorage.shared
        let resolvedServerClient = serverClient ?? AuthServerClient(
            session: CertificatePinningManager.shared.createPinnedURLSession()
        )
        let resolvedKeychain = keychain ?? KeychainManager.shared
        let resolvedDeviceIdentifier = deviceIdentifier ?? DeviceIdentifier.shared
        let resolvedChecker = integrityChecker ?? IntegrityChecker.shared

        self.integrityChecker = resolvedChecker
        self.integrityMonitor = integrityMonitor ?? IntegrityMonitor(checker: resolvedChecker)

        #if DEBUG
        self.deviceIdentifier = resolvedDeviceIdentifier
        #endif

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

        // Wire sub-manager state-change callbacks back through the reducer.
        self.trialManager.setOnStateChange { [weak self] _ in
            guard let self else { return }
            self.authState = AuthStateReducer.reduce(
                current: self.authState,
                event: .trialDeniedByServer
            )
        }
        self.licenseManager.setOnStateChange { [weak self] _ in
            guard let self else { return }
            self.authState = AuthStateReducer.reduce(
                current: self.authState,
                event: .licenseRevokedByServer(
                    trialFallback: self.trialManager.checkTrialStatus()
                )
            )
        }
    }

    // MARK: - Lifecycle

    /// Runs the initial integrity check and starts monitoring. Deferred out
    /// of `init` because the integrity check is async and must not capture
    /// a half-initialized self.
    func start() async {
        let integrityPassed = await integrityChecker.passesAllChecks()
        let licenseState = licenseManager.checkLicense()
        let trialState = trialManager.checkTrialStatus()

        authState = AuthStateReducer.reduce(
            current: authState,
            event: .startup(
                integrityPassed: integrityPassed,
                licenseState: licenseState,
                trialState: trialState
            )
        )

        // Kick off background license re-validation if we're currently authenticated.
        if case let .authenticated(licenseKey) = authState {
            licenseManager.validateLicenseInBackground(licenseKey: licenseKey)
        }

        integrityMonitor.start(interval: Self.monitoringInterval) { [weak self] in
            guard let self else { return }
            self.authState = AuthStateReducer.reduce(
                current: self.authState,
                event: .integrityMonitorFailed
            )
            await self.validateCurrentState()
        }
    }

    // MARK: - Authentication Status

    func refreshAuthenticationState() {
        if let licenseState = licenseManager.checkLicense() {
            authState = licenseState
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
            authState = AuthStateReducer.reduce(
                current: authState,
                event: .licenseActivatedLocally(licenseKey: licenseKey)
            )
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
                authState = AuthStateReducer.reduce(
                    current: authState,
                    event: .licenseRevokedByServer(trialFallback: trialManager.checkTrialStatus())
                )
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
        authState = AuthStateReducer.reduce(current: authState, event: .loggedOut)
    }
}
