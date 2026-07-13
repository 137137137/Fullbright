//
//  KeychainProviding.swift
//  Fullbright
//
//  Keychain operations protocol.
//

import Foundation

protocol KeychainProviding: Sendable {
    func save(_ data: Data, for key: String) throws(KeychainError)
    /// Returns the stored bytes, or `nil` if no item exists for `key`.
    /// Throws `KeychainError.loadFailed` for a genuine read failure — a
    /// missing item and a failed read are NOT conflated (a swallowed error
    /// would let callers treat "keychain unavailable" as "never stored").
    func load(for key: String) throws(KeychainError) -> Data?
    func delete(for key: String) throws(KeychainError)
}
