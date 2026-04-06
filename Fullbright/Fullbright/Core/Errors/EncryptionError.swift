//
//  EncryptionError.swift
//  Fullbright
//

import Foundation

enum EncryptionError: Error, LocalizedError {
    case encryptionFailed(underlying: Error)
    case decryptionFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .encryptionFailed(let underlying):
            return "Failed to encrypt data: \(underlying.localizedDescription)"
        case .decryptionFailed(let underlying):
            return "Failed to decrypt data: \(underlying.localizedDescription)"
        }
    }
}
