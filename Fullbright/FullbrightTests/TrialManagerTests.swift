//
//  TrialManagerTests.swift
//  FullbrightTests
//
//  Synchronous tests for TrialManager — start, check, debug helpers. Async
//  server confirmation paths are not exercised here (handled by
//  SecureAuthenticationManagerTests via stub state-change callbacks).
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

    // MARK: - checkTrialStatus

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
            // 14 days from now → 14 (or 13, depending on hour rounding)
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
        let (manager, storage, _, _) = makeManager()  // device-A
        let trialData = SecureTrialData(
            startDate: Date(),
            deviceId: "different-device",
            confirmed: true
        )
        try storage.saveEncrypted(trialData, for: StorageKey.trialData)
        #expect(manager.checkTrialStatus() == .expired)
    }

    // MARK: - startTrial

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
