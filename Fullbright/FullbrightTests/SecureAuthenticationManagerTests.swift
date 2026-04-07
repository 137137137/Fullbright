//
//  SecureAuthenticationManagerTests.swift
//  FullbrightTests
//

import Foundation
import Testing
@testable import Fullbright

/// Polls `condition` until it returns true or `timeout` expires. Used by
/// tests that assert eventual state transitions after async event delivery.
@MainActor
private func waitUntilState(
    of manager: SecureAuthenticationManager,
    matches expected: AuthenticationState,
    timeout: Duration = .seconds(2)
) async -> Bool {
    let start = ContinuousClock.now
    while ContinuousClock.now - start < timeout {
        if manager.authState == expected { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return manager.authState == expected
}

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

    @Test func freshlyConstructed_isNotAuthenticatedBeforeStart() {
        let (manager, _, _) = makeManager()
        #expect(manager.authState == .notAuthenticated)
    }

    @Test func start_failedIntegrityCheck_setsExpired() async {
        let (manager, _, _) = makeManager(integrityPasses: false)
        await manager.start()
        #expect(manager.authState == .expired)
    }

    @Test func start_noTrialNoLicense_remainsNotAuthenticated() async {
        let trial = StubTrialManager()
        let license = StubLicenseManager()
        license.nextCheckResult = nil
        trial.nextCheckResult = .notAuthenticated
        let (manager, _, _) = makeManager(trial: trial, license: license)
        await manager.start()
        #expect(manager.authState == .notAuthenticated)
    }

    @Test func start_withStoredLicense_becomesAuthenticated() async {
        let trial = StubTrialManager()
        let license = StubLicenseManager()
        license.nextCheckResult = .authenticated(licenseKey: "ABC")
        let (manager, _, license2) = makeManager(trial: trial, license: license)
        await manager.start()
        #expect(manager.authState == .authenticated(licenseKey: "ABC"))
        #expect(license2.validateBackgroundCallCount == 1)
    }

    @Test func start_withActiveTrial_becomesTrial() async {
        let trial = StubTrialManager()
        let license = StubLicenseManager()
        let expiry = Date(timeIntervalSinceNow: 86400 * 7)
        license.nextCheckResult = nil
        trial.nextCheckResult = .trial(daysRemaining: 7, expiryDate: expiry)
        let (manager, _, _) = makeManager(trial: trial, license: license)
        await manager.start()
        #expect(manager.authState == .trial(daysRemaining: 7, expiryDate: expiry))
    }

    @Test func startTrial_delegatesToTrialManager() {
        let trial = StubTrialManager()
        let expiry = Date(timeIntervalSinceNow: 86400 * 14)
        trial.nextStartResult = .trial(daysRemaining: 14, expiryDate: expiry)
        let (manager, trial2, _) = makeManager(trial: trial)
        manager.startTrial()
        #expect(trial2.startCallCount == 1)
        #expect(manager.authState == .trial(daysRemaining: 14, expiryDate: expiry))
    }

    @Test func logout_revokesLicenseAndExpires() {
        let license = StubLicenseManager()
        let (manager, _, license2) = makeManager(license: license)
        manager.logout()
        #expect(license2.revokeCallCount == 1)
        #expect(manager.authState == .expired)
    }

    @Test func licenseRevocation_fallsBackToTrialState() async {
        let trial = StubTrialManager()
        let license = StubLicenseManager()
        let expiry = Date(timeIntervalSinceNow: 86400 * 5)
        trial.nextCheckResult = .trial(daysRemaining: 5, expiryDate: expiry)
        let (manager, _, license2) = makeManager(trial: trial, license: license)
        await manager.start()
        license2.yield(.revokedByServer)
        let reached = await waitUntilState(
            of: manager,
            matches: .trial(daysRemaining: 5, expiryDate: expiry)
        )
        #expect(reached)
    }

    @Test func trialServerDenies_setsExpired() async {
        let trial = StubTrialManager()
        let (manager, trial2, _) = makeManager(trial: trial)
        await manager.start()
        trial2.yield(.deniedByServer)
        let reached = await waitUntilState(of: manager, matches: .expired)
        #expect(reached)
    }
}
