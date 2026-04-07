//
//  DeviceIdentifierTests.swift
//  FullbrightTests
//
//  Sanity checks for DeviceIdentifier. Full IOKit substitution is deferred
//  to Phase 4; these tests cover the public contract available today.
//

import Foundation
import Testing
@testable import Fullbright

@Suite("DeviceIdentifier")
struct DeviceIdentifierTests {

    @Test("secureIdentifier is non-empty and stable across reads")
    func secureIdentifier_isStable() {
        let id1 = DeviceIdentifier().secureIdentifier
        let id2 = DeviceIdentifier().secureIdentifier
        #expect(!id1.isEmpty)
        #expect(id1 == id2)
    }

    @Test("secureIdentifier is a 64-character hex SHA-256 digest")
    func secureIdentifier_isSHA256HexDigest() {
        let id = DeviceIdentifier().secureIdentifier
        #expect(id.count == 64)
        let hexCharacters = CharacterSet(charactersIn: "0123456789abcdef")
        #expect(id.unicodeScalars.allSatisfy { hexCharacters.contains($0) })
    }
}
