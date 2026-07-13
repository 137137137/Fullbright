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
    fileprivate let storage: any SecureStorageProviding
    private let serverClient: any TrialServerClientProviding
    private let keychain: any KeychainProviding
    fileprivate let deviceIdentifier: any DeviceIdentifying

    static let trialDurationDays = 14

    /// How far the clock may appear to move backward before we call it
    /// manipulation. Generous enough for NTP corrections and honest
    /// clock fixes; far too small to extend a 14-day trial usefully.
    static let clockRollbackTolerance: TimeInterval = 60 * 60 * 24
    /// Watermark persistence granularity — avoids rewriting the trial
    /// record on every single status check.
    private static let watermarkUpdateGranularity: TimeInterval = 60 * 60

    /// Single-subscriber event stream. See LicenseManager.events for rationale.
    let events: AsyncStream<TrialEvent>
    private let eventsContinuation: AsyncStream<TrialEvent>.Continuation

    init(storage: any SecureStorageProviding,
         serverClient: any TrialServerClientProviding,
         keychain: any KeychainProviding,
         deviceIdentifier: any DeviceIdentifying) {
        self.storage = storage
        self.serverClient = serverClient
        self.keychain = keychain
        self.deviceIdentifier = deviceIdentifier

        let (stream, continuation) = AsyncStream<TrialEvent>.makeStream(bufferingPolicy: .unbounded)
        self.events = stream
        self.eventsContinuation = continuation
    }

    /// A `nonisolated deinit` cancels this MainActor-isolated `Task`
    /// property directly (Task is Sendable).
    private var confirmationTask: Task<Void, Never>?

    nonisolated deinit {
        confirmationTask?.cancel()
        eventsContinuation.finish()
    }

    // MARK: - Trial Status

    func checkTrialStatus() -> AuthenticationState {
        if let trialData = storage.loadEncrypted(SecureTrialData.self, for: StorageKey.trialData) {
            guard trialData.isValid,
                  trialData.deviceId == deviceIdentifier.secureIdentifier else {
                return .expired
            }

            // Clock-rollback guard: `startDate` vs the wall clock alone
            // makes a trial infinite for anyone willing to set their clock
            // back. Track the highest time ever observed; a clock sitting
            // meaningfully before it means manipulation, not NTP drift.
            let now = Date()
            let watermark = trialData.latestObservedDate ?? trialData.startDate
            if now < watermark.addingTimeInterval(-Self.clockRollbackTolerance) {
                logger.warning("Clock rollback detected (now is \(Int(watermark.timeIntervalSince(now)), privacy: .public)s before watermark) — treating trial as expired")
                return .expired
            }
            if now > watermark.addingTimeInterval(Self.watermarkUpdateGranularity) {
                persistWatermark(now, for: trialData)
            }

            let state = calculateTrialState(from: trialData)
            if case .trial = state, !trialData.confirmed {
                confirmTrialWithServer(trialData: trialData)
            }
            return state
        } else {
            return .notAuthenticated
        }
    }

    /// Best-effort: a failed watermark write never blocks a valid trial.
    private func persistWatermark(_ now: Date, for trialData: SecureTrialData) {
        let updated = SecureTrialData(
            startDate: trialData.startDate,
            deviceId: trialData.deviceId,
            confirmed: trialData.confirmed,
            latestObservedDate: now
        )
        do {
            try storage.saveEncrypted(updated, for: StorageKey.trialData)
        } catch {
            logger.error("Failed to persist trial date watermark: \(error, privacy: .public)")
        }
    }

    private func calculateTrialState(from trialData: SecureTrialData) -> AuthenticationState {
        let daysSinceStart = Calendar.current.dateComponents([.day], from: trialData.startDate, to: Date()).day ?? 0
        let daysRemaining = Self.trialDurationDays - daysSinceStart

        if daysRemaining > 0 {
            guard let expiryDate = Calendar.current.date(byAdding: .day, value: Self.trialDurationDays, to: trialData.startDate) else {
                return .expired
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

    private func confirmTrialWithServer(trialData: SecureTrialData) {
        guard !trialData.confirmed else { return }

        let continuation = self.eventsContinuation
        confirmationTask?.cancel()
        confirmationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.serverClient.registerTrial(deviceId: trialData.deviceId)
            switch result {
            case .confirmed:
                let confirmed = SecureTrialData(
                    startDate: trialData.startDate,
                    deviceId: trialData.deviceId,
                    confirmed: true,
                    latestObservedDate: trialData.latestObservedDate
                )
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
                continuation.yield(.deniedByServer)
            case .offline:
                break
            }
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
