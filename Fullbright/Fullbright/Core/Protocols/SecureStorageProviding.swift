//
//  SecureStorageProviding.swift
//  Fullbright
//
//  Encrypted file storage protocol.
//

import Foundation

@MainActor
protocol SecureStorageProviding: AnyObject {
    func saveEncrypted<T: Codable>(_ object: T, for key: String) throws
    func loadEncrypted<T: Codable>(_ type: T.Type, for key: String) -> T?
    func delete(for key: String) throws
}
