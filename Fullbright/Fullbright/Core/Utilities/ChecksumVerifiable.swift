//
//  ChecksumVerifiable.swift
//  Fullbright
//
//  Checksum-based integrity verification protocol.
//

import Foundation

protocol ChecksumVerifiable {
    var checksum: String { get }
    func computeChecksum() -> String
}

extension ChecksumVerifiable {
    var isValid: Bool { checksum == computeChecksum() }
}
