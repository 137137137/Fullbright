//
//  LicenseManaging.swift
//  Fullbright
//

import Foundation

/// Core license lifecycle protocol. DEBUG helpers live in the separate
/// `DebugLicenseManaging` protocol (see SecureAuthenticationManager+Debug.swift)
/// so production conformers aren't forced to implement test affordances.
@MainActor
protocol LicenseManaging: AnyObject {
    func checkLicense() -> AuthenticationState?
    func setOnStateChange(_ handler: @escaping @MainActor (AuthenticationState) -> Void)
    func validateLicenseInBackground(licenseKey: String)
    func validateLicense(licenseKey: String) async -> LicenseValidationResult
    func activateLicense(licenseKey: String) async -> (success: Bool, message: String?)
    func revokeLicense()
}
