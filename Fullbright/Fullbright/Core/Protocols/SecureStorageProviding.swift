//
//  SecureStorageProviding.swift
//  Fullbright
//
//  Encrypted file storage protocol.
//

import Foundation

/// Encrypted storage. `async` so implementations can run AES-GCM/HKDF and
/// file I/O off the main actor (see `SecureFileStorage`, an `actor`).
protocol SecureStorageProviding: Sendable {
    func saveEncrypted<T: Encodable & Sendable>(_ object: T, for key: String) async throws
    // `Codable` (not just `Decodable`): a legacy v1 record is transparently
    // re-saved as v2 on read, which requires the payload to be Encodable too.
    func loadEncrypted<T: Codable & Sendable>(_ type: T.Type, for key: String) async -> T?
    func delete(for key: String) async throws
}
