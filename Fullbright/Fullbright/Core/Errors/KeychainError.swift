//
//  KeychainError.swift
//  Fullbright
//

import Foundation

enum KeychainError: LocalizedError, Sendable {
    case saveFailed(status: OSStatus)
    case loadFailed(status: OSStatus)
    case deleteFailed(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Keychain save failed (status: \(status))"
        case .loadFailed(let status):
            return "Keychain load failed (status: \(status))"
        case .deleteFailed(let status):
            return "Keychain delete failed (status: \(status))"
        }
    }
}
