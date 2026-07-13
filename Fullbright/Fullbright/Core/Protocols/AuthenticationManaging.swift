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
    /// Async because the initial integrity check is offloaded to a
    /// detached task (SecStaticCodeCheckValidity is blocking).
    func start() async

    func refreshAuthenticationState() async
    func startTrial() async
    func activateLicense(licenseKey: String) async -> LicenseActivationResult
    func logout() async
}

// MARK: - Debug-Only Extensions

#if DEBUG
@MainActor
protocol DebugAuthManaging: AuthenticationManaging {
    func setTrialDaysRemaining(_ days: Int) async
    func resetTrial() async
    func expireTrial() async
    func setValidLicense() async
    func printDebugInfo() async
}

/// Debug auth actions shared by both view models.
@MainActor
struct DebugAuthActions {
    private let authManager: any AuthenticationManaging

    init(authManager: any AuthenticationManaging) {
        self.authManager = authManager
    }

    private var debug: (any DebugAuthManaging)? { authManager as? any DebugAuthManaging }

    func setTrialDays(_ days: Int) async { await debug?.setTrialDaysRemaining(days) }
    func expireTrial() async { await debug?.expireTrial() }
    func resetTrial() async { await debug?.resetTrial() }
    func setValidLicense() async { await debug?.setValidLicense() }
    func clearLicense() async { await authManager.logout() }
    func printInfo() async { await debug?.printDebugInfo() }
}
#endif
