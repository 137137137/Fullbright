//
//  EncryptionError.swift
//  Fullbright
//

import Foundation

enum EncryptionError: LocalizedError {
    case encryptionFailed(underlying: any Error)
    case decryptionFailed(underlying: any Error)
    /// `AES.GCM.SealedBox.combined` returned nil — the sealed box has no
    /// combined (nonce + ciphertext + tag) representation to persist.
    case combinedRepresentationUnavailable

    var errorDescription: String? {
        switch self {
        case .encryptionFailed(let underlying):
            return "Failed to encrypt data: \(underlying.localizedDescription)"
        case .decryptionFailed(let underlying):
            return "Failed to decrypt data: \(underlying.localizedDescription)"
        case .combinedRepresentationUnavailable:
            return "Failed to encrypt data: sealed box has no combined representation"
        }
    }
}
