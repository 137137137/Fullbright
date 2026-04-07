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
    let storage: any SecureStorageProviding
    private let serverClient: any LicenseValidationClientProviding & LicenseActivationClientProviding
    let deviceIdentifier: any DeviceIdentifying

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

    /// Wrapped in an OSAllocatedUnfairLock so the `nonisolated deinit` can
    /// cancel an in-flight validation task without violating the MainActor
    /// isolation of `LicenseManager` itself. Matches the pattern in
    /// SecureAuthenticationManager.
    private let validationTaskLock = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)

    nonisolated deinit {
        validationTaskLock.withLock { $0?.cancel() }
        eventsContinuation.finish()
    }

    func validateLicenseInBackground(licenseKey: String) {
        let continuation = self.eventsContinuation
        let task = Task { @MainActor [weak self] in
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
        // Replace any prior task atomically and cancel it.
        validationTaskLock.withLock { existing in
            existing?.cancel()
            existing = task
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
