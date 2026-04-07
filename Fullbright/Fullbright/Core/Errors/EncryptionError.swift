//
//  EncryptionError.swift
//  Fullbright
//

import Foundation

enum EncryptionError: Error, LocalizedError {
    case encryptionFailed(underlying: any Error)
    case decryptionFailed(underlying: any Error)

    var errorDescription: String? {
        switch self {
        case .encryptionFailed(let underlying):
            return "Failed to encrypt data: \(underlying.localizedDescription)"
        case .decryptionFailed(let underlying):
            return "Failed to decrypt data: \(underlying.localizedDescription)"
        }
    }
}
