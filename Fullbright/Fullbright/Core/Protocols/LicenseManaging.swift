//
//  LicenseManaging.swift
//  Fullbright
//

import Foundation

/// Events published by a LicenseManaging conformer. Currently there is one:
/// `revokedByServer`, emitted when a background validation discovers the
/// server has invalidated the license.
enum LicenseEvent: Sendable, Equatable {
    case revokedByServer
}

/// Core license lifecycle protocol. DEBUG helpers live in the separate
/// `DebugLicenseManaging` protocol (see SecureAuthenticationManager+Debug.swift)
/// so production conformers aren't forced to implement test affordances.
///
/// State-change notifications come via the `events` AsyncStream rather than
/// a callback. The stream has a single subscriber (the auth coordinator);
/// broadcasting to multiple observers is not supported by design.
@MainActor
protocol LicenseManaging: AnyObject {
    func checkLicense() -> AuthenticationState?
    var events: AsyncStream<LicenseEvent> { get }
    func validateLicenseInBackground(licenseKey: String)
    func validateLicense(licenseKey: String) async -> LicenseValidationResult
    func activateLicense(licenseKey: String) async -> (success: Bool, message: String?)
    func revokeLicense()
}
