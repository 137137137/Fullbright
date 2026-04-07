//
//  LicenseManager.swift
//  Fullbright
//
//  License lifecycle: activation, validation, revocation.
//

import Foundation
import os

private let logger = Logger(subsystem: AppIdentifier.serviceID, category: "License")

@MainActor
final class LicenseManager: LicenseManaging {
    private let storage: any SecureStorageProviding
    private let serverClient: any LicenseValidationClientProviding & LicenseActivationClientProviding
    private let deviceIdentifier: any DeviceIdentifying


    init(storage: any SecureStorageProviding,
         serverClient: any LicenseValidationClientProviding & LicenseActivationClientProviding,
         deviceIdentifier: any DeviceIdentifying) {
        self.storage = storage
        self.serverClient = serverClient
        self.deviceIdentifier = deviceIdentifier
    }

    // MARK: - License Check

    /// Returns the license state if a valid license exists, nil otherwise.
    func checkLicense() -> AuthenticationState? {
        guard let licenseData = storage.loadEncrypted(SecureLicenseData.self, for: StorageKey.licenseData) else {
            return nil
        }

        if licenseData.isValid && licenseData.deviceId == deviceIdentifier.secureIdentifier {
            return .authenticated(licenseKey: licenseData.licenseKey)
        } else {
            do {
                try storage.delete(for: StorageKey.licenseData)
            } catch {
                logger.error("Failed to delete corrupt license data: \(error, privacy: .public)")
            }
            return nil
        }
    }

    // MARK: - License Validation

    /// Callback to notify the auth manager when license state changes from server response
    private(set) var onStateChange: (@MainActor (AuthenticationState) -> Void)?

    func setOnStateChange(_ handler: @escaping @MainActor (AuthenticationState) -> Void) {
        onStateChange = handler
    }

    private var validationTask: Task<Void, Never>?

    deinit { validationTask?.cancel() }

    func validateLicenseInBackground(licenseKey: String) {
        validationTask?.cancel()
        validationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.serverClient.validateLicense(
                licenseKey: licenseKey,
                deviceId: self.deviceIdentifier.secureIdentifier
            )
            if case .invalid = result {
                do {
                    try self.storage.delete(for: StorageKey.licenseData)
                } catch {
                    logger.error("Failed to delete invalid license: \(error, privacy: .public)")
                }
                self.onStateChange?(.expired)
            }
        }
    }

    /// Validate license synchronously (for periodic state validation)
    func validateLicense(licenseKey: String) async -> LicenseValidationResult {
        await serverClient.validateLicense(
            licenseKey: licenseKey,
            deviceId: deviceIdentifier.secureIdentifier
        )
    }

    // MARK: - License Activation

    func activateLicense(licenseKey: String) async -> (success: Bool, message: String?) {
        let deviceId = deviceIdentifier.secureIdentifier
        let result = await serverClient.activateLicense(licenseKey: licenseKey, deviceId: deviceId)

        switch result {
        case .success:
            let licenseData = SecureLicenseData(
                licenseKey: licenseKey,
                activationDate: Date(),
                deviceId: deviceId
            )
            do {
                try storage.saveEncrypted(licenseData, for: StorageKey.licenseData)
            } catch {
                logger.error("Failed to persist license data: \(error, privacy: .public)")
                return (false, "License activated but failed to save locally. Please try again.")
            }
            return (true, nil)
        case .failure(let message):
            return (false, message)
        }
    }

    // MARK: - License Revocation

    func revokeLicense() {
        do {
            try storage.delete(for: StorageKey.licenseData)
        } catch {
            logger.error("Failed to delete license data on logout: \(error, privacy: .public)")
        }
    }

    // MARK: - Debug Helpers

    #if DEBUG
    func debugLicenseInfo() -> String {
        if let licenseData = self.storage.loadEncrypted(SecureLicenseData.self, for: StorageKey.licenseData) {
            return """
            License Key: \(licenseData.licenseKey)
            Activation Date: \(licenseData.activationDate)
            Data Valid: \(licenseData.isValid)
            """
        }
        return "No license data"
    }

    func setValidLicense() {
        let licenseData = SecureLicenseData(
            licenseKey: DebugConstants.testLicenseKey,
            activationDate: Date(),
            deviceId: deviceIdentifier.secureIdentifier
        )
        try? storage.saveEncrypted(licenseData, for: StorageKey.licenseData)
    }
    #endif
}
