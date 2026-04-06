//
//  Checksum.swift
//  Fullbright
//
//  SHA-256 checksum utility.
//

import Foundation
import CryptoKit

enum Checksum {
    /// SHA-256 hash of the input string, returned as a lowercase hex string.
    static func sha256(_ input: String) -> String {
        sha256(Data(input.utf8))
    }

    /// SHA-256 hash of raw data, returned as a lowercase hex string.
    static func sha256(_ data: Data) -> String {
        CryptoKit.SHA256.hash(data: data).hexString
    }
}
