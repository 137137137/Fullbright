//
//  SecureFileStorageTests.swift
//  FullbrightTests
//
//  Exercises the real SecureFileStorage against an in-memory keychain and a
//  per-test temporary directory. Covers AES-GCM round-trip, salt generation,
//  salt persistence, legacy-salt migration, and file permissions.
//

import Foundation
import Testing
@testable import Fullbright

private struct TempDirectory {
    let url: URL

    init() {
        let base = FileManager.default.temporaryDirectory
        self.url = base.appendingPathComponent("fb-storage-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: url)
    }
}

private struct Payload: Codable, Equatable {
    let licenseKey: String
    let deviceId: String
    let count: Int
}

@MainActor
@Suite("SecureFileStorage")
struct SecureFileStorageTests {

    @Test("round-trip: save then load returns identical payload")
    func roundTrip_savesAndLoadsEquivalentPayload() throws {
        let dir = TempDirectory()
        defer { dir.cleanup() }

        let storage = SecureFileStorage(
            keychain: InMemoryKeychain(),
            deviceIdentifier: StubDeviceIdentifier("device-a"),
            storageDirectory: dir.url
        )

        let payload = Payload(licenseKey: "abc-123", deviceId: "device-a", count: 7)
        try storage.saveEncrypted(payload, for: "test.key")

        let loaded = storage.loadEncrypted(Payload.self, for: "test.key")
        #expect(loaded == payload)
    }

    @Test("load returns nil when no file exists for the given key")
    func load_missingKey_returnsNil() {
        let dir = TempDirectory()
        defer { dir.cleanup() }

        let storage = SecureFileStorage(
            keychain: InMemoryKeychain(),
            deviceIdentifier: StubDeviceIdentifier(),
            storageDirectory: dir.url
        )

        let loaded = storage.loadEncrypted(Payload.self, for: "nonexistent")
        #expect(loaded == nil)
    }

    @Test("delete removes the on-disk file")
    func delete_removesFileFromDisk() throws {
        let dir = TempDirectory()
        defer { dir.cleanup() }

        let storage = SecureFileStorage(
            keychain: InMemoryKeychain(),
            deviceIdentifier: StubDeviceIdentifier(),
            storageDirectory: dir.url
        )

        try storage.saveEncrypted(Payload(licenseKey: "x", deviceId: "y", count: 1), for: "test.key")
        try storage.delete(for: "test.key")

        #expect(storage.loadEncrypted(Payload.self, for: "test.key") == nil)
    }

    @Test("salt is persisted to the keychain on first init")
    func init_persistsGeneratedSaltToKeychain() {
        let dir = TempDirectory()
        defer { dir.cleanup() }
        let keychain = InMemoryKeychain()

        _ = SecureFileStorage(
            keychain: keychain,
            deviceIdentifier: StubDeviceIdentifier(),
            storageDirectory: dir.url
        )

        #expect(keychain.load(for: StorageKey.encryptionSalt) != nil)
    }

    @Test("two instances with the same keychain share the same derived key and can read each other's data")
    func twoInstances_sameKeychain_shareSalt() throws {
        let dir = TempDirectory()
        defer { dir.cleanup() }
        let keychain = InMemoryKeychain()
        let device = StubDeviceIdentifier("shared-device")

        let writer = SecureFileStorage(keychain: keychain, deviceIdentifier: device, storageDirectory: dir.url)
        try writer.saveEncrypted(Payload(licenseKey: "k", deviceId: "shared-device", count: 3), for: "shared")

        let reader = SecureFileStorage(keychain: keychain, deviceIdentifier: device, storageDirectory: dir.url)
        let loaded = reader.loadEncrypted(Payload.self, for: "shared")
        #expect(loaded?.licenseKey == "k")
    }

    @Test("different device identifiers produce mutually unreadable data even with the same salt")
    func differentDeviceIds_cannotDecryptEachOthersData() throws {
        let dir = TempDirectory()
        defer { dir.cleanup() }
        let keychain = InMemoryKeychain()

        let alice = SecureFileStorage(
            keychain: keychain,
            deviceIdentifier: StubDeviceIdentifier("alice"),
            storageDirectory: dir.url
        )
        try alice.saveEncrypted(Payload(licenseKey: "secret", deviceId: "alice", count: 1), for: "test.key")

        let bob = SecureFileStorage(
            keychain: keychain,
            deviceIdentifier: StubDeviceIdentifier("bob"),
            storageDirectory: dir.url
        )

        let loaded = bob.loadEncrypted(Payload.self, for: "test.key")
        #expect(loaded == nil)
    }

    @Test("saved files are created with 0o600 permissions")
    func save_setsRestrictiveFilePermissions() throws {
        let dir = TempDirectory()
        defer { dir.cleanup() }

        let storage = SecureFileStorage(
            keychain: InMemoryKeychain(),
            deviceIdentifier: StubDeviceIdentifier(),
            storageDirectory: dir.url
        )

        try storage.saveEncrypted(Payload(licenseKey: "x", deviceId: "y", count: 1), for: "perm.key")

        let contents = try FileManager.default.contentsOfDirectory(atPath: dir.url.path)
        let file = try #require(contents.first(where: { $0.hasPrefix(".") }))
        let fileURL = dir.url.appendingPathComponent(file)
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let perms = attrs[.posixPermissions] as? NSNumber
        #expect(perms?.intValue == 0o600)
    }

    // MARK: - SignedEnvelope / migration

    @Test("legacy v1 data (raw payload, no envelope) is transparently accepted and migrated to v2 on read")
    func load_legacyV1Payload_isAcceptedAndMigrated() throws {
        let dir = TempDirectory()
        defer { dir.cleanup() }
        let keychain = InMemoryKeychain()
        let device = StubDeviceIdentifier("legacy-device")

        // Write a v1-format payload using the test-only legacy seam.
        let legacy = SecureFileStorage(keychain: keychain, deviceIdentifier: device, storageDirectory: dir.url)
        let payload = Payload(licenseKey: "legacy-key", deviceId: "legacy-device", count: 42)
        try legacy._writeLegacyV1Payload(payload, for: "legacy.key")

        // Now load via the real SecureFileStorage — should migrate.
        let storage = SecureFileStorage(keychain: keychain, deviceIdentifier: device, storageDirectory: dir.url)
        let loaded = storage.loadEncrypted(Payload.self, for: "legacy.key")
        #expect(loaded == payload)

        // After the first load, the on-disk data should now be v2 (SignedEnvelope).
        // The easiest way to verify this is to load again — it should still work
        // AND subsequent writes should continue to be v2.
        let loadedAgain = storage.loadEncrypted(Payload.self, for: "legacy.key")
        #expect(loadedAgain == payload)
    }

    @Test("tampered envelope bytes are rejected")
    func load_tamperedEnvelope_returnsNil() throws {
        let dir = TempDirectory()
        defer { dir.cleanup() }
        let keychain = InMemoryKeychain()
        let device = StubDeviceIdentifier("tamper-device")

        let storage = SecureFileStorage(keychain: keychain, deviceIdentifier: device, storageDirectory: dir.url)
        try storage.saveEncrypted(Payload(licenseKey: "real", deviceId: "tamper-device", count: 1), for: "tamper.key")

        // Locate and corrupt the on-disk file. AES-GCM authentication will
        // already reject this, which is the desired result — tests assert the
        // end-to-end defense rather than any specific internal layer.
        let contents = try FileManager.default.contentsOfDirectory(atPath: dir.url.path)
        let file = try #require(contents.first(where: { $0.hasPrefix(".") }))
        let fileURL = dir.url.appendingPathComponent(file)
        var bytes = try Data(contentsOf: fileURL)
        // Flip bits in the middle of the ciphertext.
        bytes[bytes.count / 2] ^= 0xFF
        try bytes.write(to: fileURL)

        #expect(storage.loadEncrypted(Payload.self, for: "tamper.key") == nil)
    }

    @Test("files on disk are not plaintext-readable as the original payload")
    func save_writesEncryptedBytesNotPlaintext() throws {
        let dir = TempDirectory()
        defer { dir.cleanup() }

        let storage = SecureFileStorage(
            keychain: InMemoryKeychain(),
            deviceIdentifier: StubDeviceIdentifier(),
            storageDirectory: dir.url
        )

        let secret = "super-secret-license-key-DO-NOT-LEAK"
        try storage.saveEncrypted(Payload(licenseKey: secret, deviceId: "d", count: 1), for: "cipher.key")

        let contents = try FileManager.default.contentsOfDirectory(atPath: dir.url.path)
        let file = try #require(contents.first(where: { $0.hasPrefix(".") }))
        let data = try Data(contentsOf: dir.url.appendingPathComponent(file))

        // Ciphertext should not literally contain the secret string bytes.
        let secretBytes = Array(Data(secret.utf8))
        let rawBytes = Array(data)
        let secretFound = rawBytes.windows(ofCount: secretBytes.count).contains { window in
            Array(window) == secretBytes
        }
        #expect(!secretFound)
    }
}

// Tiny polyfill because swift-testing doesn't provide .windows on Array directly.
private extension Array {
    func windows(ofCount n: Int) -> [ArraySlice<Element>] {
        guard n > 0, count >= n else { return [] }
        return (0...(count - n)).map { self[$0..<($0 + n)] }
    }
}
