//
//  TrialManager.swift
//  Fullbright
//
//  Trial lifecycle: start, status check, server confirmation, expiry.
//

import Foundation
import os

private let logger = Logger(subsystem: AppIdentifier.serviceID, category: "Trial")

@MainActor
final class TrialManager: TrialManaging {
    private let storage: any SecureStorageProviding
    private let serverClient: any TrialServerClientProviding
    private let keychain: any KeychainProviding
    private let deviceIdentifier: any DeviceIdentifying

    private static let trialDurationDays = 14

    init(storage: any SecureStorageProviding,
         serverClient: any TrialServerClientProviding,
         keychain: any KeychainProviding,
         deviceIdentifier: any DeviceIdentifying) {
        self.storage = storage
        self.serverClient = serverClient
        self.keychain = keychain
        self.deviceIdentifier = deviceIdentifier
    }

    /// See LicenseManager.validationTaskLock for the rationale.
    private let confirmationTaskLock = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)

    nonisolated deinit {
        confirmationTaskLock.withLock { $0?.cancel() }
    }

    // MARK: - Trial Status

    func checkTrialStatus() -> AuthenticationState {
        if let trialData = storage.loadEncrypted(SecureTrialData.self, for: StorageKey.trialData) {
            guard trialData.isValid,
                  trialData.deviceId == deviceIdentifier.secureIdentifier else {
                return .expired
            }
            return calculateTrialState(from: trialData)
        } else {
            return .notAuthenticated
        }
    }

    private func calculateTrialState(from trialData: SecureTrialData) -> AuthenticationState {
        let daysSinceStart = Calendar.current.dateComponents([.day], from: trialData.startDate, to: Date()).day ?? 0
        let daysRemaining = Self.trialDurationDays - daysSinceStart

        if daysRemaining > 0 {
            guard let expiryDate = Calendar.current.date(byAdding: .day, value: Self.trialDurationDays, to: trialData.startDate) else {
                return .expired
            }

            if !trialData.confirmed {
                confirmTrialWithServer(trialData: trialData)
            }

            return .trial(daysRemaining: daysRemaining, expiryDate: expiryDate)
        } else {
            return .expired
        }
    }

    // MARK: - Start Trial

    func startTrial() -> AuthenticationState {
        let deviceId = deviceIdentifier.secureIdentifier

        if keychain.load(for: StorageKey.trialUsed) != nil {
            return .expired
        }

        do {
            try keychain.save(Data([1]), for: StorageKey.trialUsed)
        } catch {
            logger.error("Failed to save trial-used flag — denying trial: \(error, privacy: .public)")
            return .expired
        }

        let trialData = SecureTrialData(startDate: Date(), deviceId: deviceId, confirmed: false)
        do {
            try storage.saveEncrypted(trialData, for: StorageKey.trialData)
        } catch {
            logger.error("Failed to save trial data: \(error, privacy: .public)")
            return .expired
        }

        guard let expiryDate = Calendar.current.date(byAdding: .day, value: Self.trialDurationDays, to: Date()) else {
            return .expired
        }

        confirmTrialWithServer(trialData: trialData)
        return .trial(daysRemaining: Self.trialDurationDays, expiryDate: expiryDate)
    }

    // MARK: - Server Confirmation

    /// Callback to notify the auth manager when trial state changes from server response
    private(set) var onStateChange: (@MainActor (AuthenticationState) -> Void)?

    func setOnStateChange(_ handler: @escaping @MainActor (AuthenticationState) -> Void) {
        onStateChange = handler
    }

    private func confirmTrialWithServer(trialData: SecureTrialData) {
        guard !trialData.confirmed else { return }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.serverClient.registerTrial(deviceId: trialData.deviceId)
            switch result {
            case .confirmed:
                let confirmed = SecureTrialData(startDate: trialData.startDate, deviceId: trialData.deviceId, confirmed: true)
                do {
                    try self.storage.saveEncrypted(confirmed, for: StorageKey.trialData)
                } catch {
                    logger.error("Failed to persist trial confirmation: \(error, privacy: .public)")
                }
            case .denied:
                do {
                    try self.storage.delete(for: StorageKey.trialData)
                } catch {
                    logger.error("Failed to delete denied trial data: \(error, privacy: .public)")
                }
                self.onStateChange?(.expired)
            case .offline:
                break
            }
        }
        confirmationTaskLock.withLock { existing in
            existing?.cancel()
            existing = task
        }
    }

}

#if DEBUG
extension TrialManager: DebugTrialManaging {
    func setTrialDaysRemaining(_ days: Int) -> AuthenticationState {
        guard let startDate = Calendar.current.date(byAdding: .day, value: -(Self.trialDurationDays - days), to: Date()) else {
            return .expired
        }
        let trialData = SecureTrialData(startDate: startDate, deviceId: deviceIdentifier.secureIdentifier)
        try? storage.saveEncrypted(trialData, for: StorageKey.trialData)
        return checkTrialStatus()
    }

    func expireTrial() -> AuthenticationState {
        guard let expiredDate = Calendar.current.date(byAdding: .day, value: -(Self.trialDurationDays + 1), to: Date()) else {
            return .expired
        }
        let trialData = SecureTrialData(startDate: expiredDate, deviceId: deviceIdentifier.secureIdentifier)
        try? storage.saveEncrypted(trialData, for: StorageKey.trialData)
        return checkTrialStatus()
    }

    func resetTrial() {
        try? storage.delete(for: StorageKey.trialData)
    }

    var trialDuration: Int { Self.trialDurationDays }

    func debugTrialInfo() -> String {
        if let trialData = self.storage.loadEncrypted(SecureTrialData.self, for: StorageKey.trialData) {
            let daysSince = Calendar.current.dateComponents([.day], from: trialData.startDate, to: Date()).day ?? 0
            return """
            Trial Start: \(trialData.startDate)
            Days Since Start: \(daysSince)
            Days Remaining: \(Self.trialDurationDays - daysSince)
            Data Valid: \(trialData.isValid)
            """
        }
        return "No trial data"
    }
}
#endif
