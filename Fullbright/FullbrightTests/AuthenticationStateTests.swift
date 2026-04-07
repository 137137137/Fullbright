//
//  AuthenticationStateTests.swift
//  FullbrightTests
//

import Foundation
import Testing
@testable import Fullbright

struct AuthenticationStateTests {

    @Test func canUseXDR_authenticated_isTrue() {
        #expect(AuthenticationState.authenticated(licenseKey: "ABC").canUseXDR)
    }

    @Test func canUseXDR_trial_isTrue() {
        let state = AuthenticationState.trial(daysRemaining: 7, expiryDate: Date())
        #expect(state.canUseXDR)
    }

    @Test func canUseXDR_expired_isFalse() {
        #expect(AuthenticationState.expired.canUseXDR == false)
    }

    @Test func canUseXDR_notAuthenticated_isFalse() {
        #expect(AuthenticationState.notAuthenticated.canUseXDR == false)
    }

    @Test func isTrialUrgent_zeroDays_isTrue() {
        #expect(AuthenticationState.trial(daysRemaining: 0, expiryDate: Date()).isTrialUrgent)
    }

    @Test func isTrialUrgent_threeDays_isTrue() {
        #expect(AuthenticationState.trial(daysRemaining: 3, expiryDate: Date()).isTrialUrgent)
    }

    @Test func isTrialUrgent_fourDays_isFalse() {
        #expect(AuthenticationState.trial(daysRemaining: 4, expiryDate: Date()).isTrialUrgent == false)
    }

    @Test func isTrialUrgent_fourteenDays_isFalse() {
        #expect(AuthenticationState.trial(daysRemaining: 14, expiryDate: Date()).isTrialUrgent == false)
    }

    @Test func isTrialUrgent_authenticated_isFalse() {
        #expect(AuthenticationState.authenticated(licenseKey: "X").isTrialUrgent == false)
    }

    @Test func isTrialUrgent_expired_isFalse() {
        #expect(AuthenticationState.expired.isTrialUrgent == false)
    }

    @Test func isAuthenticated_onlyAuthenticatedCase() {
        #expect(AuthenticationState.authenticated(licenseKey: "X").isAuthenticated)
        #expect(AuthenticationState.notAuthenticated.isAuthenticated == false)
        #expect(AuthenticationState.expired.isAuthenticated == false)
        let trial = AuthenticationState.trial(daysRemaining: 5, expiryDate: Date())
        #expect(trial.isAuthenticated == false)
    }

    @Test func equatable_distinguishesTrialDays() {
        let date = Date()
        let a = AuthenticationState.trial(daysRemaining: 5, expiryDate: date)
        let b = AuthenticationState.trial(daysRemaining: 6, expiryDate: date)
        #expect(a != b)
    }

    @Test func equatable_distinguishesLicenseKeys() {
        #expect(AuthenticationState.authenticated(licenseKey: "A")
                != AuthenticationState.authenticated(licenseKey: "B"))
    }
}
