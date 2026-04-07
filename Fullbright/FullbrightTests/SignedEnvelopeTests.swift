//
//  SignedEnvelopeTests.swift
//  FullbrightTests
//

import Foundation
import CryptoKit
import Testing
@testable import Fullbright

@Suite("SignedEnvelope")
struct SignedEnvelopeTests {

    private func makeSigner() -> HMACPayloadSigner {
        HMACPayloadSigner(key: SymmetricKey(size: .bits256))
    }

    @Test("wrap then unwrap round-trips successfully")
    func wrapThenUnwrap_roundTrip() throws {
        let signer = makeSigner()
        let original = "test payload"
        let envelope = try SignedEnvelope.wrap(original, signer: signer)
        let unwrapped = try envelope.unwrap(String.self, signer: signer)
        #expect(unwrapped == original)
    }

    @Test("tampered payload fails verification")
    func tamperedPayload_failsVerification() throws {
        let signer = makeSigner()
        let envelope = try SignedEnvelope.wrap("original", signer: signer)

        // Create a tampered envelope by reconstructing with different payload but same signature
        let tampered = SignedEnvelope(
            version: SignedEnvelope.currentVersion,
            payloadJSON: Data("\"tampered\"".utf8),
            signature: envelope.signature
        )

        #expect(throws: SignedEnvelopeError.self) {
            _ = try tampered.unwrap(String.self, signer: signer)
        }
    }

    @Test("wrong signer key fails verification")
    func wrongSignerKey_failsVerification() throws {
        let signer1 = makeSigner()
        let signer2 = makeSigner()
        let envelope = try SignedEnvelope.wrap("payload", signer: signer1)

        #expect(throws: SignedEnvelopeError.self) {
            _ = try envelope.unwrap(String.self, signer: signer2)
        }
    }
}
