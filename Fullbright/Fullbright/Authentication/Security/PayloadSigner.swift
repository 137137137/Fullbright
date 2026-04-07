//
//  PayloadSigner.swift
//  Fullbright
//
//  HMAC-SHA256 payload signing for SignedEnvelope.
//
//  Rationale: AES-GCM (used by SecureFileStorage for encryption-at-rest)
//  already provides authenticated encryption. However, if the encryption
//  key is ever compromised, an attacker could forge arbitrary ciphertext.
//  A separate HMAC key — derived from the same master material via HKDF
//  with a distinct info parameter — provides defense-in-depth: forging a
//  valid SignedEnvelope requires BOTH keys.
//
//  The plain SHA-256 "checksum" previously used on SecureLicenseData /
//  SecureTrialData is NOT a MAC and provides no integrity guarantee
//  against an attacker with write access to the payload. It remains as
//  legacy v1 data but new data is always signed via HMAC.
//

import Foundation
import CryptoKit

protocol PayloadSigner: Sendable {
    func sign(_ data: Data) -> Data
    func verify(_ data: Data, signature: Data) -> Bool
}

struct HMACPayloadSigner: PayloadSigner {
    private let key: SymmetricKey

    init(key: SymmetricKey) {
        self.key = key
    }

    func sign(_ data: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: data, using: key))
    }

    func verify(_ data: Data, signature: Data) -> Bool {
        HMAC<SHA256>.isValidAuthenticationCode(signature, authenticating: data, using: key)
    }
}
