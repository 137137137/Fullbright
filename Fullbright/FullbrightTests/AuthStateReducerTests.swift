//
//  AuthStateReducerTests.swift
//  FullbrightTests
//
//  Exhaustive (state, event) → next-state coverage. Pure, no I/O.
//

import Foundation
import Testing
@testable import Fullbright

@Suite("AuthStateReducer")
struct AuthStateReducerTests {

    // MARK: - Startup

    @Test("startup with integrity failure always yields .expired")
    func startup_integrityFailure_expires() {
        let next = AuthStateReducer.reduce(
            current: .notAuthenticated,
            event: .startup(
                integrityPassed: false,
                licenseState: .authenticated(licenseKey: "K"),
                trialState: .trial(daysRemaining: 5, expiryDate: Date())
            )
        )
        #expect(next == .expired)
    }

    @Test("startup with license state present uses license over trial")
    func startup_licensePresent_prefersLicense() {
        let next = AuthStateReducer.reduce(
            current: .notAuthenticated,
            event: .startup(
                integrityPassed: true,
                licenseState: .authenticated(licenseKey: "LK"),
                trialState: .trial(daysRemaining: 3, expiryDate: Date())
            )
        )
        #expect(next == .authenticated(licenseKey: "LK"))
    }

    @Test("startup with no license falls through to trial state")
    func startup_noLicense_usesTrial() {
        let expiry = Date(timeIntervalSinceNow: 86400 * 5)
        let next = AuthStateReducer.reduce(
            current: .notAuthenticated,
            event: .startup(
                integrityPassed: true,
                licenseState: nil,
                trialState: .trial(daysRemaining: 5, expiryDate: expiry)
            )
        )
        #expect(next == .trial(daysRemaining: 5, expiryDate: expiry))
    }

    @Test("startup with no license and notAuthenticated trial state stays notAuthenticated")
    func startup_noLicense_noTrial_staysNotAuthenticated() {
        let next = AuthStateReducer.reduce(
            current: .notAuthenticated,
            event: .startup(
                integrityPassed: true,
                licenseState: nil,
                trialState: .notAuthenticated
            )
        )
        #expect(next == .notAuthenticated)
    }

    @Test("startup with no license and expired trial state yields .expired")
    func startup_noLicense_expiredTrial_expires() {
        let next = AuthStateReducer.reduce(
            current: .notAuthenticated,
            event: .startup(
                integrityPassed: true,
                licenseState: nil,
                trialState: .expired
            )
        )
        #expect(next == .expired)
    }

    // MARK: - License revocation by server

    @Test("license revoked by server with valid trial fallback drops to trial")
    func licenseRevoked_withTrialFallback_dropsToTrial() {
        let expiry = Date(timeIntervalSinceNow: 86400 * 2)
        let next = AuthStateReducer.reduce(
            current: .authenticated(licenseKey: "K"),
            event: .licenseRevokedByServer(
                trialFallback: .trial(daysRemaining: 2, expiryDate: expiry)
            )
        )
        #expect(next == .trial(daysRemaining: 2, expiryDate: expiry))
    }

    @Test("license revoked by server with expired trial fallback yields .expired")
    func licenseRevoked_withExpiredTrial_expires() {
        let next = AuthStateReducer.reduce(
            current: .authenticated(licenseKey: "K"),
            event: .licenseRevokedByServer(trialFallback: .expired)
        )
        #expect(next == .expired)
    }

    @Test("license revoked by server with notAuthenticated fallback yields notAuthenticated")
    func licenseRevoked_withNoTrial_isNotAuthenticated() {
        let next = AuthStateReducer.reduce(
            current: .authenticated(licenseKey: "K"),
            event: .licenseRevokedByServer(trialFallback: .notAuthenticated)
        )
        #expect(next == .notAuthenticated)
    }

    // MARK: - Trial denied by server

    @Test("trial denied by server yields .expired from any state")
    func trialDenied_fromAnyState_expires() {
        let states: [AuthenticationState] = [
            .notAuthenticated,
            .trial(daysRemaining: 7, expiryDate: Date()),
            .authenticated(licenseKey: "K"),
            .expired
        ]
        for state in states {
            let next = AuthStateReducer.reduce(current: state, event: .trialDeniedByServer)
            #expect(next == .expired, "unexpected transition from \(state)")
        }
    }

    // MARK: - License activated locally

    @Test("license activated locally yields authenticated with key")
    func licenseActivated_yieldsAuthenticated() {
        let next = AuthStateReducer.reduce(
            current: .trial(daysRemaining: 1, expiryDate: Date()),
            event: .licenseActivatedLocally(licenseKey: "NEW-KEY")
        )
        #expect(next == .authenticated(licenseKey: "NEW-KEY"))
    }

    @Test("license activated locally from expired state still yields authenticated")
    func licenseActivated_fromExpired_yieldsAuthenticated() {
        let next = AuthStateReducer.reduce(
            current: .expired,
            event: .licenseActivatedLocally(licenseKey: "ABC")
        )
        #expect(next == .authenticated(licenseKey: "ABC"))
    }

    // MARK: - Logout

    @Test("logout yields .expired from any state")
    func logout_fromAnyState_expires() {
        let states: [AuthenticationState] = [
            .notAuthenticated,
            .trial(daysRemaining: 7, expiryDate: Date()),
            .authenticated(licenseKey: "K"),
            .expired
        ]
        for state in states {
            let next = AuthStateReducer.reduce(current: state, event: .loggedOut)
            #expect(next == .expired, "unexpected transition from \(state)")
        }
    }

    // MARK: - Integrity monitor failure

    @Test("integrity monitor failure yields .expired from any state")
    func integrityFailure_fromAnyState_expires() {
        let states: [AuthenticationState] = [
            .notAuthenticated,
            .trial(daysRemaining: 7, expiryDate: Date()),
            .authenticated(licenseKey: "K"),
            .expired
        ]
        for state in states {
            let next = AuthStateReducer.reduce(current: state, event: .integrityMonitorFailed)
            #expect(next == .expired, "unexpected transition from \(state)")
        }
    }
}
