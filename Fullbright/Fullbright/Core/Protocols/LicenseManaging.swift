//
//  LicenseManaging.swift
//  Fullbright
//

import Foundation

@MainActor
protocol LicenseManaging: AnyObject {
    func checkLicense() -> AuthenticationState?
    func setOnStateChange(_ handler: @escaping @MainActor (AuthenticationState) -> Void)
    func validateLicenseInBackground(licenseKey: String)
    func validateLicense(licenseKey: String) async -> LicenseValidationResult
    func activateLicense(licenseKey: String) async -> (success: Bool, message: String?)
    func revokeLicense()

    #if DEBUG
    func debugLicenseInfo() -> String
    func setValidLicense()
    #endif
}
