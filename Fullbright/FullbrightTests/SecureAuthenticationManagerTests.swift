//
//  SecureAuthenticationManagerTests.swift
//  FullbrightTests
//
//  Tests for the auth state machine driven by injected stubs for the
//  trial/license managers, integrity checker, and storage.
//

import Foundation
import Testing
@testable import Fullbright

@MainActor
struct SecureAuthenticationManagerTests {

    private func makeManager(
        integrityPasses: Bool = true,
        trial: StubTrialManager? = nil,
        license: StubLicenseManager? = nil
    ) -> (SecureAuthenticationManager, StubTrialManager, StubLicenseManager) {
        let trialManager = trial ?? StubTrialManager()
        let licenseManager = license ?? StubLicenseManager()
        let manager = SecureAuthenticationManager(
            storage: InMemorySecureStorage(),
            serverClient: StubAuthServerClient(),
            keychain: InMemoryKeychain(),
            integrityChecker: StubIntegrityChecker(passes: integrityPasses),
            deviceIdentifier: StubDeviceIdentifier(),
            trialManager: trialManager,
            licenseManager: licenseManager
        )
        return (manager, trialManager, licenseManager)
    }

    // MARK: - Initial state

    @Test func freshlyConstructed_isNotAuthenticatedBeforeStart() {
        let (manager, _, _) = makeManager()
        // Per the deferred-init contract, no checks have run yet.
        #expect(manager.authState == .notAuthenticated)
    }

    // MARK: - start()

    @Test func start_failedIntegrityCheck_setsExpired() {
        let (manager, _, _) = makeManager(integrityPasses: false)
        manager.start()
        #expect(manager.authState == .expired)
    }

    @Test func start_noTrialNoLicense_remainsNotAuthenticated() {
        let trial = StubTrialManager()
        let license = StubLicenseManager()
        license.nextCheckResult = nil
        trial.nextCheckResult = .notAuthenticated
        let (manager, _, _) = makeManager(trial: trial, license: license)
        manager.start()
        #expect(manager.authState == .notAuthenticated)
    }

    @Test func start_withStoredLicense_becomesAuthenticated() {
        let trial = StubTrialManager()
        let license = StubLicenseManager()
        license.nextCheckResult = .authenticated(licenseKey: "ABC")
        let (manager, _, license2) = makeManager(trial: trial, license: license)
        manager.start()
        #expect(manager.authState == .authenticated(licenseKey: "ABC"))
        // Background validation should be kicked off when authenticated.
        #expect(license2.validateBackgroundCallCount == 1)
    }

    @Test func start_withActiveTrial_becomesTrial() {
        let trial = StubTrialManager()
        let license = StubLicenseManager()
        let expiry = Date(timeIntervalSinceNow: 86400 * 7)
        license.nextCheckResult = nil
        trial.nextCheckResult = .trial(daysRemaining: 7, expiryDate: expiry)
        let (manager, _, _) = makeManager(trial: trial, license: license)
        manager.start()
        #expect(manager.authState == .trial(daysRemaining: 7, expiryDate: expiry))
    }

    // MARK: - startTrial()

    @Test func startTrial_delegatesToTrialManager() {
        let trial = StubTrialManager()
        let expiry = Date(timeIntervalSinceNow: 86400 * 14)
        trial.nextStartResult = .trial(daysRemaining: 14, expiryDate: expiry)
        let (manager, trial2, _) = makeManager(trial: trial)
        manager.startTrial()
        #expect(trial2.startCallCount == 1)
        #expect(manager.authState == .trial(daysRemaining: 14, expiryDate: expiry))
    }

    // MARK: - logout()

    @Test func logout_revokesLicenseAndExpires() {
        let license = StubLicenseManager()
        let (manager, _, license2) = makeManager(license: license)
        manager.logout()
        #expect(license2.revokeCallCount == 1)
        #expect(manager.authState == .expired)
    }

    // MARK: - State change callbacks

    @Test func licenseRevocation_fallsBackToTrialState() {
        let trial = StubTrialManager()
        let license = StubLicenseManager()
        let expiry = Date(timeIntervalSinceNow: 86400 * 5)
        trial.nextCheckResult = .trial(daysRemaining: 5, expiryDate: expiry)
        let (manager, _, license2) = makeManager(trial: trial, license: license)
        manager.start()
        // Simulate a server-side license revocation
        license2.emitStateChange(.expired)
        // The handler in SecureAuthenticationManager checks the trial as a fallback
        #expect(manager.authState == .trial(daysRemaining: 5, expiryDate: expiry))
    }

    @Test func trialServerDenies_setsExpired() {
        let trial = StubTrialManager()
        let (manager, trial2, _) = makeManager(trial: trial)
        manager.start()
        trial2.emitStateChange(.expired)
        #expect(manager.authState == .expired)
    }
}
