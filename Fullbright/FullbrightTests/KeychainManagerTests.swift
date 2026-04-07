//
//  KeychainManagerTests.swift
//  FullbrightTests
//
//  Integration tests against the real macOS Keychain. Each test uses a
//  UUID-suffixed account so tests never collide with each other or with
//  real app data. The suite is serialized because it touches shared state.
//

import Foundation
import Testing
@testable import Fullbright

@Suite("KeychainManager", .serialized)
struct KeychainManagerTests {

    private func scopedKey() -> String {
        "fb-test-\(UUID().uuidString)"
    }

    @Test("save then load returns the same bytes")
    func saveLoad_roundTrip() throws {
        let keychain = KeychainManager.shared
        let key = scopedKey()
        defer { try? keychain.delete(for: key) }

        let data = Data("hello-world".utf8)
        try keychain.save(data, for: key)
        #expect(keychain.load(for: key) == data)
    }

    @Test("load returns nil for an unknown key")
    func load_unknownKey_isNil() {
        #expect(KeychainManager.shared.load(for: "fb-test-unknown-\(UUID().uuidString)") == nil)
    }

    @Test("save overwrites an existing value at the same key")
    func save_overwritesExistingValue() throws {
        let keychain = KeychainManager.shared
        let key = scopedKey()
        defer { try? keychain.delete(for: key) }

        try keychain.save(Data("first".utf8), for: key)
        try keychain.save(Data("second".utf8), for: key)
        #expect(keychain.load(for: key) == Data("second".utf8))
    }

    @Test("delete removes the value; load then returns nil")
    func delete_removesValue() throws {
        let keychain = KeychainManager.shared
        let key = scopedKey()

        try keychain.save(Data("to-be-deleted".utf8), for: key)
        try keychain.delete(for: key)
        #expect(keychain.load(for: key) == nil)
    }

    @Test("delete on a missing key does not throw")
    func delete_missingKey_doesNotThrow() {
        #expect(throws: Never.self) {
            try KeychainManager.shared.delete(for: "fb-test-nope-\(UUID().uuidString)")
        }
    }
}
