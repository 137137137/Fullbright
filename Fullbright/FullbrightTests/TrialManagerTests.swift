//
//  TrialManagerTests.swift
//  FullbrightTests
//

import Foundation
import Testing
@testable import Fullbright

@MainActor
struct TrialManagerTests {

    private func makeManager(
        deviceId: String = "device-A"
    ) -> (TrialManager, InMemorySecureStorage, InMemoryKeychain, StubAuthServerClient) {
        let storage = InMemorySecureStorage()
        let keychain = InMemoryKeychain()
        let server = StubAuthServerClient()
        let manager = TrialManager(
            storage: storage,
            serverClient: server,
            keychain: keychain,
            deviceIdentifier: StubDeviceIdentifier(deviceId)
        )
        return (manager, storage, keychain, server)
    }

    @Test func checkTrialStatus_noStoredData_isNotAuthenticated() {
        let (manager, _, _, _) = makeManager()
        #expect(manager.checkTrialStatus() == .notAuthenticated)
    }

    @Test func checkTrialStatus_freshTrial_returnsTrialState() throws {
        let (manager, storage, _, _) = makeManager()
        let trialData = SecureTrialData(
            startDate: Date(),
            deviceId: "device-A",
            confirmed: true
        )
        try storage.saveEncrypted(trialData, for: StorageKey.trialData)

        let state = manager.checkTrialStatus()
        if case .trial(let daysRemaining, _) = state {
            #expect(daysRemaining >= 13 && daysRemaining <= 14)
        } else {
            Issue.record("Expected .trial state, got \(state)")
        }
    }

    @Test func checkTrialStatus_expiredTrial_returnsExpired() throws {
        let (manager, storage, _, _) = makeManager()
        let oldStart = Calendar.current.date(byAdding: .day, value: -20, to: Date())!
        let trialData = SecureTrialData(
            startDate: oldStart,
            deviceId: "device-A",
            confirmed: true
        )
        try storage.saveEncrypted(trialData, for: StorageKey.trialData)
        #expect(manager.checkTrialStatus() == .expired)
    }

    @Test func checkTrialStatus_deviceMismatch_returnsExpired() throws {
        let (manager, storage, _, _) = makeManager()
        let trialData = SecureTrialData(
            startDate: Date(),
            deviceId: "different-device",
            confirmed: true
        )
        try storage.saveEncrypted(trialData, for: StorageKey.trialData)
        #expect(manager.checkTrialStatus() == .expired)
    }

    @Test func checkTrialStatus_clockRolledBackPastWatermark_returnsExpired() throws {
        let (manager, storage, _, _) = makeManager()
        // The trial has already seen a wall-clock 3 days in the future —
        // i.e. the user ran the app, then set the clock back 3 days.
        let trialData = SecureTrialData(
            startDate: Calendar.current.date(byAdding: .day, value: -2, to: Date())!,
            deviceId: "device-A",
            confirmed: true,
            latestObservedDate: Date().addingTimeInterval(3 * 86400)
        )
        try storage.saveEncrypted(trialData, for: StorageKey.trialData)
        #expect(manager.checkTrialStatus() == .expired)
    }

    @Test func checkTrialStatus_smallClockDrift_withinTolerance_staysTrial() throws {
        let (manager, storage, _, _) = makeManager()
        // Watermark 2 hours ahead of "now" — inside the 24h tolerance
        // (NTP correction, honest clock fix).
        let trialData = SecureTrialData(
            startDate: Calendar.current.date(byAdding: .day, value: -2, to: Date())!,
            deviceId: "device-A",
            confirmed: true,
            latestObservedDate: Date().addingTimeInterval(2 * 3600)
        )
        try storage.saveEncrypted(trialData, for: StorageKey.trialData)
        if case .trial = manager.checkTrialStatus() {} else {
            Issue.record("Expected .trial despite small clock drift")
        }
    }

    @Test func checkTrialStatus_advancesWatermark() throws {
        let (manager, storage, _, _) = makeManager()
        let trialData = SecureTrialData(
            startDate: Calendar.current.date(byAdding: .day, value: -5, to: Date())!,
            deviceId: "device-A",
            confirmed: true,
            latestObservedDate: Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        )
        try storage.saveEncrypted(trialData, for: StorageKey.trialData)
        _ = manager.checkTrialStatus()

        let stored = storage.loadEncrypted(SecureTrialData.self, for: StorageKey.trialData)
        let watermark = try #require(stored?.latestObservedDate)
        #expect(abs(watermark.timeIntervalSinceNow) < 60)
        // Start date and confirmation state survive the watermark rewrite.
        #expect(stored?.startDate == trialData.startDate)
        #expect(stored?.confirmed == true)
    }

    @Test func checkTrialStatus_legacyRecordWithoutWatermark_stillWorks() throws {
        let (manager, storage, _, _) = makeManager()
        // Simulates a record written by a build predating the watermark.
        let trialData = SecureTrialData(
            startDate: Date(),
            deviceId: "device-A",
            confirmed: true,
            latestObservedDate: nil
        )
        try storage.saveEncrypted(trialData, for: StorageKey.trialData)
        if case .trial = manager.checkTrialStatus() {} else {
            Issue.record("Expected .trial for legacy record")
        }
    }

    @Test func startTrial_freshDevice_returnsTrialState() {
        let (manager, _, _, _) = makeManager()
        let state = manager.startTrial()
        if case .trial(let daysRemaining, _) = state {
            #expect(daysRemaining == 14)
        } else {
            Issue.record("Expected .trial state, got \(state)")
        }
    }

    @Test func startTrial_persistsTrialData() {
        let (manager, storage, _, _) = makeManager()
        _ = manager.startTrial()
        let stored = storage.loadEncrypted(SecureTrialData.self, for: StorageKey.trialData)
        #expect(stored != nil)
        #expect(stored?.deviceId == "device-A")
    }

    @Test func startTrial_setsTrialUsedFlagInKeychain() {
        let (manager, _, keychain, _) = makeManager()
        _ = manager.startTrial()
        #expect(keychain.load(for: StorageKey.trialUsed) != nil)
    }

    @Test func startTrial_alreadyUsed_returnsExpired() throws {
        let (manager, _, keychain, _) = makeManager()
        try keychain.save(Data([1]), for: StorageKey.trialUsed)
        let state = manager.startTrial()
        #expect(state == .expired)
    }
}
