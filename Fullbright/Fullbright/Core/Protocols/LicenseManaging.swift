//
//  LicenseManaging.swift
//  Fullbright
//
//  License manager protocol — enables injection and testability of
//  the license activation/validation/revocation flow.
//

import Foundation

@MainActor
protocol LicenseManaging: AnyObject {
    /// Returns the license state if a valid license exists locally, nil otherwise.
    func checkLicense() -> AuthenticationState?

    /// Registers a callback for asynchronous state changes from server responses.
    func setOnStateChange(_ handler: @escaping @MainActor (AuthenticationState) -> Void)

    /// Validates a license against the server in the background.
    /// State changes (e.g. revocation) are delivered via `onStateChange`.
    func validateLicenseInBackground(licenseKey: String)

    /// Validates a license against the server synchronously (for periodic checks).
    func validateLicense(licenseKey: String) async -> LicenseValidationResult

    /// Activates a license against the server and persists on success.
    func activateLicense(licenseKey: String) async -> (success: Bool, message: String?)

    /// Removes the persisted license data.
    func revokeLicense()

    #if DEBUG
    func debugLicenseInfo() -> String
    func setValidLicense()
    #endif
}
