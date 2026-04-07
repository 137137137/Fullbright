//
//  SignedEnvelope.swift
//  Fullbright
//
//  Generic HMAC-signed wrapper for any Codable payload written to
//  SecureFileStorage. The envelope is transparent to callers — they
//  continue to pass raw payloads into saveEncrypted/loadEncrypted and
//  receive raw payloads back.
//
//  On-disk format (after AES-GCM decryption):
//    {
//      "version": 2,
//      "payloadJSON": <base64 JSON bytes of the payload>,
//      "signature":   <base64 HMAC-SHA256 of payloadJSON>
//    }
//
//  We store the payload as opaque JSON bytes (rather than a nested
//  Codable value) so that the HMAC covers the exact bytes used for both
//  encode and decode. This avoids any Swift-level key-ordering or
//  encoding ambiguity.
//

import Foundation

struct SignedEnvelope: Codable, Sendable {
    static let currentVersion = 2

    let version: Int
    let payloadJSON: Data
    let signature: Data

    /// Wraps a Codable payload by JSON-encoding it and signing the bytes.
    static func wrap<T: Encodable>(_ payload: T, signer: any PayloadSigner) throws -> SignedEnvelope {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payloadBytes = try encoder.encode(payload)
        let signature = signer.sign(payloadBytes)
        return SignedEnvelope(
            version: currentVersion,
            payloadJSON: payloadBytes,
            signature: signature
        )
    }

    /// Verifies the signature and decodes the inner payload.
    /// Throws SignedEnvelopeError.signatureMismatch on tamper or key mismatch.
    func unwrap<T: Decodable>(_ type: T.Type, signer: any PayloadSigner) throws -> T {
        guard signer.verify(payloadJSON, signature: signature) else {
            throw SignedEnvelopeError.signatureMismatch
        }
        return try JSONDecoder().decode(type, from: payloadJSON)
    }
}

enum SignedEnvelopeError: Error, LocalizedError {
    case signatureMismatch
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .signatureMismatch:
            return "Payload signature verification failed — data has been tampered with or the signing key has changed."
        case .unsupportedVersion(let v):
            return "Unsupported SignedEnvelope version: \(v)."
        }
    }
}
