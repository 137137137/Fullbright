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
        var result = ""
        result.reserveCapacity(Self.byteCount * 2)
        for byte in self {
            result.append(String(format: "%02x", byte))
        }
        return result
    }
}
