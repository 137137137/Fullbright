//
//  SecureAuthenticationManager+Debug.swift
//  Fullbright
//
//  DEBUG-only helpers for manual QA and UI test harnesses. Kept in a
//  separate file so the production manager stays free of test-only
//  methods.
//

#if DEBUG

import Foundation
import os

private let debugLogger = Logger(subsystem: AppIdentifier.serviceID, category: "AuthDebug")

extension SecureAuthenticationManager: DebugAuthManaging {

    func setTrialDaysRemaining(_ days: Int) {
        guard let debug = trialManager as? any DebugTrialManaging else { return }
        authState = debug.setTrialDaysRemaining(days)
        debugLogger.debug("Trial set to \(days, privacy: .public) days remaining")
    }

    func resetTrial() {
        (trialManager as? any DebugTrialManaging)?.resetTrial()
        licenseManager.revokeLicense()
        authState = .notAuthenticated
        refreshAuthenticationState()
        debugLogger.debug("Trial reset - app will behave as first launch")
    }

    func expireTrial() {
        guard let debug = trialManager as? any DebugTrialManaging else { return }
        authState = debug.expireTrial()
        debugLogger.debug("Trial expired")
    }

    func setValidLicense() {
        (licenseManager as? any DebugLicenseManaging)?.setValidLicense()
        authState = .authenticated(licenseKey: DebugConstants.testLicenseKey)
        debugLogger.debug("Test license activated")
    }

    func printDebugInfo() {
        let deviceId = deviceIdentifier.secureIdentifier
        let trialInfo = (trialManager as? any DebugTrialManaging)?.debugTrialInfo() ?? "(no trial debug info)"
        let licenseInfo = (licenseManager as? any DebugLicenseManaging)?.debugLicenseInfo() ?? "(no license debug info)"
        debugLogger.debug("=== Authentication Debug Info ===")
        debugLogger.debug("Current State: \(String(describing: self.authState), privacy: .public)")
        debugLogger.debug("Device ID: \(deviceId)")
        debugLogger.debug("\(trialInfo)")
        debugLogger.debug("\(licenseInfo)")
        debugLogger.debug("================================")
    }
}

// MARK: - Focused DEBUG-only sub-protocols

/// DEBUG-only operations on TrialManaging. Kept out of the core TrialManaging
/// protocol so every production conformer doesn't have to implement test
/// affordances under #if DEBUG guards.
@MainActor
protocol DebugTrialManaging {
    func setTrialDaysRemaining(_ days: Int) -> AuthenticationState
    func expireTrial() -> AuthenticationState
    func resetTrial()
    var trialDuration: Int { get }
    func debugTrialInfo() -> String
}

/// DEBUG-only operations on LicenseManaging. Same rationale.
@MainActor
protocol DebugLicenseManaging {
    func debugLicenseInfo() -> String
    func setValidLicense()
}

#endif
