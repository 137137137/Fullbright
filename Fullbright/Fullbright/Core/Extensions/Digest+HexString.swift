//
//  Digest+HexString.swift
//  Fullbright
//
//  Hex-string conversion for CryptoKit digests.
//

import Foundation
import CryptoKit

extension Digest {
    /// Lowercase hex string representation of the digest bytes.
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
