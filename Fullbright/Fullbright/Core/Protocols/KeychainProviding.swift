//
//  KeychainProviding.swift
//  Fullbright
//
//  Keychain operations protocol.
//

import Foundation

protocol KeychainProviding: Sendable {
    func save(_ data: Data, for key: String) throws
    func load(for key: String) -> Data?
    func delete(for key: String) throws
}
