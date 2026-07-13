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

    func setTrialDaysRemaining(_ days: Int) async {
        guard let debug = trialManager as? any DebugTrialManaging else { return }
        authState = await debug.setTrialDaysRemaining(days)
        debugLogger.debug("Trial set to \(days, privacy: .public) days remaining")
    }

    func resetTrial() async {
        await (trialManager as? any DebugTrialManaging)?.resetTrial()
        await licenseManager.revokeLicense()
        authState = .notAuthenticated
        await refreshAuthenticationState()
        debugLogger.debug("Trial reset - app will behave as first launch")
    }

    func expireTrial() async {
        guard let debug = trialManager as? any DebugTrialManaging else { return }
        authState = await debug.expireTrial()
        debugLogger.debug("Trial expired")
    }

    func setValidLicense() async {
        await (licenseManager as? any DebugLicenseManaging)?.setValidLicense()
        authState = .authenticated(licenseKey: DebugConstants.testLicenseKey)
        debugLogger.debug("Test license activated")
    }

    func printDebugInfo() async {
        let deviceId = deviceIdentifier.secureIdentifier
        let trialInfo = await (trialManager as? any DebugTrialManaging)?.debugTrialInfo() ?? "(no trial debug info)"
        let licenseInfo = await (licenseManager as? any DebugLicenseManaging)?.debugLicenseInfo() ?? "(no license debug info)"
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
    func setTrialDaysRemaining(_ days: Int) async -> AuthenticationState
    func expireTrial() async -> AuthenticationState
    func resetTrial() async
    var trialDuration: Int { get }
    func debugTrialInfo() async -> String
}

/// DEBUG-only operations on LicenseManaging. Same rationale.
@MainActor
protocol DebugLicenseManaging {
    func debugLicenseInfo() async -> String
    func setValidLicense() async
}

#endif
