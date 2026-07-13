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
        let hexDigits = Array("0123456789abcdef".utf8)
        var chars: [UInt8] = []
        chars.reserveCapacity(Self.byteCount * 2)
        for byte in self {
            chars.append(hexDigits[Int(byte >> 4)])
            chars.append(hexDigits[Int(byte & 0x0f)])
        }
        return String(decoding: chars, as: UTF8.self)
    }
}
