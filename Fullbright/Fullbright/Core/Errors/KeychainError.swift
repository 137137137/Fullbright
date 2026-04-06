//
//  KeychainError.swift
//  Fullbright
//

import Foundation

enum KeychainError: Error, LocalizedError {
    case saveFailed(status: OSStatus)
    case deleteFailed(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Keychain save failed (status: \(status))"
        case .deleteFailed(let status):
            return "Keychain delete failed (status: \(status))"
        }
    }
}
