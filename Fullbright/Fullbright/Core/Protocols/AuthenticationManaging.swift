//
//  AuthenticationManaging.swift
//  Fullbright
//
//  Authentication manager protocol.
//

import Foundation

@MainActor
protocol AuthenticationManaging: AnyObject {
    var authState: AuthenticationState { get }

    /// Runs the initial auth check and starts background monitoring.
    /// Call once from the composition root after construction.
    func start()

    func refreshAuthenticationState()
    func startTrial()
    func activateLicense(licenseKey: String) async -> (success: Bool, message: String?)
    func logout()
}

// MARK: - Debug-Only Extensions

#if DEBUG
@MainActor
protocol DebugAuthManaging: AuthenticationManaging {
    func setTrialDaysRemaining(_ days: Int)
    func resetTrial()
    func expireTrial()
    func setValidLicense()
    func printDebugInfo()
}

/// Debug auth actions shared by both view models.
@MainActor
struct DebugAuthActions {
    private let authManager: any AuthenticationManaging

    init(authManager: any AuthenticationManaging) {
        self.authManager = authManager
    }

    private var debug: (any DebugAuthManaging)? { authManager as? any DebugAuthManaging }

    func setTrialDays(_ days: Int) { debug?.setTrialDaysRemaining(days) }
    func expireTrial() { debug?.expireTrial() }
    func resetTrial() { debug?.resetTrial() }
    func setValidLicense() { debug?.setValidLicense() }
    func clearLicense() { authManager.logout() }
    func printInfo() { debug?.printDebugInfo() }
}
#endif
