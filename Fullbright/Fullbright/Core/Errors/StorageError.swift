//
//  StorageError.swift
//  Fullbright
//

import Foundation

enum StorageError: Error, LocalizedError {
    case encodingFailed(underlying: Error)
    case decodingFailed(underlying: Error)
    case saveFailed(underlying: Error)
    case deleteFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .encodingFailed(let error):
            return "Failed to encode object: \(error.localizedDescription)"
        case .decodingFailed(let error):
            return "Failed to decode object: \(error.localizedDescription)"
        case .saveFailed(let error):
            return "Failed to save data: \(error.localizedDescription)"
        case .deleteFailed(let error):
            return "Failed to delete data: \(error.localizedDescription)"
        }
    }
}
