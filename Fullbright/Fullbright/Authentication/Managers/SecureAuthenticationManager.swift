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

    @ObservationIgnored
    private let integrityCheckTaskLock = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)

    /// Tasks observing `licenseManager.events` and `trialManager.events`.
    /// Wrapped in a lock so `nonisolated deinit` can cancel them safely.
    @ObservationIgnored
    private let eventObserverTasksLock = OSAllocatedUnfairLock<[Task<Void, Never>]>(initialState: [])

    nonisolated deinit {
        integrityCheckTaskLock.withLock { $0?.cancel() }
        eventObserverTasksLock.withLock { tasks in
            for task in tasks { task.cancel() }
            tasks = []
        }
    }

    /// All dependencies are required — no fallback construction.
    /// Production wiring lives in `AppComposition.makeDependencies`;
    /// tests wire up their own doubles.
    init(integrityChecker: any IntegrityChecking,
         integrityMonitor: any IntegrityMonitoring,
         deviceIdentifier: any DeviceIdentifying,
         trialManager: any TrialManaging,
         licenseManager: any LicenseManaging) {
        self.integrityChecker = integrityChecker
        self.integrityMonitor = integrityMonitor

        #if DEBUG
        self.deviceIdentifier = deviceIdentifier
        #endif

        self.trialManager = trialManager
        self.licenseManager = licenseManager
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

        // Observe event streams from the sub-managers. Each lives for the
        // lifetime of SecureAuthenticationManager and is cancelled in deinit.
        startObservingSubManagerEvents()
    }

    private func startObservingSubManagerEvents() {
        let licenseEvents = licenseManager.events
        let trialEvents = trialManager.events

        let licenseTask = Task { @MainActor [weak self] in
            for await event in licenseEvents {
                guard let self else { return }
                switch event {
                case .revokedByServer:
                    self.authState = AuthStateReducer.reduce(
                        current: self.authState,
                        event: .licenseRevokedByServer(
                            trialFallback: self.trialManager.checkTrialStatus()
                        )
                    )
                }
            }
        }

        let trialTask = Task { @MainActor [weak self] in
            for await event in trialEvents {
                guard let self else { return }
                switch event {
                case .deniedByServer:
                    self.authState = AuthStateReducer.reduce(
                        current: self.authState,
                        event: .trialDeniedByServer
                    )
                }
            }
        }

        eventObserverTasksLock.withLock { tasks in
            // Cancel any tasks left from a previous start().
            for task in tasks { task.cancel() }
            tasks = [licenseTask, trialTask]
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

    func activateLicense(licenseKey: String) async -> LicenseActivationResult {
        let result = await licenseManager.activateLicense(licenseKey: licenseKey)
        if case .success = result {
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
