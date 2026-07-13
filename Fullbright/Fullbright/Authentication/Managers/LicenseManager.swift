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
    fileprivate let storage: any SecureStorageProviding
    private let serverClient: any LicenseValidationClientProviding & LicenseActivationClientProviding
    fileprivate let deviceIdentifier: any DeviceIdentifying

    /// Single-subscriber event stream. The continuation is used to yield
    /// events from background tasks; `events` is exposed to the auth
    /// coordinator for observation.
    let events: AsyncStream<LicenseEvent>
    private let eventsContinuation: AsyncStream<LicenseEvent>.Continuation

    init(storage: any SecureStorageProviding,
         serverClient: any LicenseValidationClientProviding & LicenseActivationClientProviding,
         deviceIdentifier: any DeviceIdentifying) {
        self.storage = storage
        self.serverClient = serverClient
        self.deviceIdentifier = deviceIdentifier

        let (stream, continuation) = AsyncStream<LicenseEvent>.makeStream(bufferingPolicy: .unbounded)
        self.events = stream
        self.eventsContinuation = continuation
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

    /// A `nonisolated deinit` can cancel this MainActor-isolated `Task`
    /// property directly (Task is Sendable), so an in-flight validation is
    /// torn down when LicenseManager is released.
    private var validationTask: Task<Void, Never>?

    nonisolated deinit {
        validationTask?.cancel()
        eventsContinuation.finish()
    }

    func validateLicenseInBackground(licenseKey: String) {
        let continuation = self.eventsContinuation
        // Replace any prior task and cancel it.
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
                continuation.yield(.revokedByServer)
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

    func activateLicense(licenseKey: String) async -> LicenseActivationResult {
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
                return .failure(message: "License activated but failed to save locally. Please try again.")
            }
            return .success
        case .failure(let message):
            return .failure(message: message)
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

}

#if DEBUG
extension LicenseManager: DebugLicenseManaging {
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
}
#endif
