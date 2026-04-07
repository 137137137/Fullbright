//
//  LicenseManagerTests.swift
//  FullbrightTests
//

import Foundation
import Testing
@testable import Fullbright

@MainActor
struct LicenseManagerTests {

    private func makeManager(
        deviceId: String = "device-A"
    ) -> (LicenseManager, InMemorySecureStorage, StubAuthServerClient) {
        let storage = InMemorySecureStorage()
        let server = StubAuthServerClient()
        let manager = LicenseManager(
            storage: storage,
            serverClient: server,
            deviceIdentifier: StubDeviceIdentifier(deviceId)
        )
        return (manager, storage, server)
    }

    @Test func checkLicense_noStoredData_isNil() {
        let (manager, _, _) = makeManager()
        #expect(manager.checkLicense() == nil)
    }

    @Test func checkLicense_validStoredLicense_returnsAuthenticated() throws {
        let (manager, storage, _) = makeManager()
        let licenseData = SecureLicenseData(
            licenseKey: "MY-KEY",
            activationDate: Date(),
            deviceId: "device-A"
        )
        try storage.saveEncrypted(licenseData, for: StorageKey.licenseData)
        #expect(manager.checkLicense() == .authenticated(licenseKey: "MY-KEY"))
    }

    @Test func checkLicense_deviceMismatch_returnsNilAndDeletesData() throws {
        let (manager, storage, _) = makeManager()
        let licenseData = SecureLicenseData(
            licenseKey: "MY-KEY",
            activationDate: Date(),
            deviceId: "OTHER-DEVICE"
        )
        try storage.saveEncrypted(licenseData, for: StorageKey.licenseData)
        #expect(manager.checkLicense() == nil)
        #expect(storage.loadEncrypted(SecureLicenseData.self, for: StorageKey.licenseData) == nil)
    }

    @Test func activateLicense_serverSuccess_persistsAndReturnsSuccess() async {
        let (manager, storage, server) = makeManager()
        server.setActivation(.success)
        let result = await manager.activateLicense(licenseKey: "NEW-KEY")
        if case .failure = result { Issue.record("Expected .success") }
        let stored = storage.loadEncrypted(SecureLicenseData.self, for: StorageKey.licenseData)
        #expect(stored?.licenseKey == "NEW-KEY")
    }

    @Test func activateLicense_serverFailure_returnsFailureWithoutPersisting() async {
        let (manager, storage, server) = makeManager()
        server.setActivation(.failure(message: "License already in use"))
        let result = await manager.activateLicense(licenseKey: "BAD-KEY")
        if case .failure(let message) = result {
            #expect(message == "License already in use")
        } else {
            Issue.record("Expected .failure")
        }
        let stored = storage.loadEncrypted(SecureLicenseData.self, for: StorageKey.licenseData)
        #expect(stored == nil)
    }

    @Test func revokeLicense_removesStoredData() throws {
        let (manager, storage, _) = makeManager()
        let licenseData = SecureLicenseData(
            licenseKey: "K",
            activationDate: Date(),
            deviceId: "device-A"
        )
        try storage.saveEncrypted(licenseData, for: StorageKey.licenseData)
        manager.revokeLicense()
        #expect(storage.loadEncrypted(SecureLicenseData.self, for: StorageKey.licenseData) == nil)
    }
}
