//
//  CertificatePinningManager.swift
//  Fullbright
//
//  Certificate pinning for fullbright.app to prevent MITM attacks.
//  Uses public key pinning (resilient to certificate renewal).
//

import Foundation
import Security
import CryptoKit
import os.log

private let logger = Logger(subsystem: AppIdentifier.serviceID, category: "CertificatePinning")

/// @unchecked Sendable is safe because all stored properties are `let` constants
/// (pinnedLeafSPKIHashes, pinnedHosts). NSObject base has no mutable state.
/// URLSessionDelegate callbacks execute on URLSession's delegate queue.
final class CertificatePinningManager: NSObject, URLSessionDelegate, @unchecked Sendable {

    /// SPKI (Subject Public Key Info) SHA-256 hashes of the **leaf** certificates
    /// we accept for pinned hosts. The validator REQUIRES one of these to match
    /// the leaf cert presented by the server — matching only an intermediate or
    /// root is rejected.
    ///
    /// Why leaf-only: the previous version accepted any certificate in the chain
    /// that matched a pinned hash, including the ISRG Root X1 root CA. That
    /// effectively allowed *any* Let's Encrypt-issued certificate for *any*
    /// domain to pass pinning, defeating the purpose.
    ///
    /// Stability: the production server runs `certbot renew` with
    /// `reuse_key = True` (configured 2026-04-07 in
    /// `/etc/letsencrypt/renewal/fullbright.app.conf`), so the leaf SPKI is
    /// preserved across cert renewals. Rotating the leaf requires:
    ///   1. Generate a new key offline.
    ///   2. Add its SPKI hash to `backupLeafSPKIHashes` and ship an app release.
    ///   3. After users have updated, swap the server key and remove the old
    ///      hash on a subsequent app release.
    ///
    /// Compute the hash with:
    ///   openssl pkey -in privkey.pem -pubout -outform DER | openssl dgst -sha256 -binary | base64
    private let pinnedLeafSPKIHashes: Set<String> = [
        // fullbright.app + www.fullbright.app current leaf SPKI (ECDSA P-256, 2025-2026)
        "7ViLqIK5wzSE/uUM1XgRpkS7xJEIGE/f5JW3DTrhSiU="
    ]

    /// Backup pin slot — populate BEFORE rotating the production key. Empty by
    /// default. The validator accepts any leaf matching either set.
    private let backupLeafSPKIHashes: Set<String> = [
        // Pre-generate with: openssl ecparam -genkey -name prime256v1 -noout -out backup.key
        // (intentionally empty until first rotation)
    ]

    /// Hostnames whose connections must satisfy leaf SPKI pinning.
    private let pinnedHosts: Set<String> = [
        "fullbright.app",
        "www.fullbright.app",
        "api.fullbright.app"
    ]

    override init() {
        super.init()
    }

    // MARK: - SPKI prefixes

    /// SubjectPublicKeyInfo DER prefix for an ECDSA P-256 public key. This is
    /// the bytes that wrap the raw 65-byte X9.63 uncompressed point so the
    /// resulting structure matches what `openssl pkey -pubout -outform DER`
    /// emits — and therefore what the pinned base64 hashes are computed from.
    ///
    /// This wrapper is necessary because `SecKeyCopyExternalRepresentation`
    /// returns the bare X9.63 point for ECDSA keys (NOT the SPKI DER). Hashing
    /// the raw point yields a different value than the canonical SPKI hash
    /// used by every other pinning implementation, which is why the previous
    /// version of this file produced hashes that never matched any real cert.
    private static let ecdsaP256SPKIPrefix: [UInt8] = [
        0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86,
        0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x08, 0x2a,
        0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03,
        0x42, 0x00
    ]

    // MARK: - Test seam

    /// Exposes the leaf-validation logic so it can be unit-tested without a
    /// live TLS handshake. Production callers go through urlSession(_:didReceive:).
    func validateLeafSPKI(_ chain: [SecCertificate]) -> Bool {
        guard let leaf = chain.first else {
            logger.error("Empty certificate chain")
            return false
        }
        guard let leafHash = Self.spkiHash(of: leaf) else {
            logger.error("Failed to compute SPKI hash for leaf certificate")
            return false
        }
        let accepted = pinnedLeafSPKIHashes.contains(leafHash) || backupLeafSPKIHashes.contains(leafHash)
        if !accepted {
            logger.error("Leaf SPKI hash does not match any pinned leaf: \(leafHash, privacy: .public)")
        }
        return accepted
    }

    /// Computes the standard base64-encoded SHA-256 of a certificate's
    /// SubjectPublicKeyInfo DER. Currently supports ECDSA P-256 keys (the
    /// only key type used by fullbright.app's Let's Encrypt certs). Returns
    /// nil for unsupported key types so the validator fails closed.
    private static func spkiHash(of certificate: SecCertificate) -> String? {
        guard let publicKey = SecCertificateCopyKey(certificate),
              let raw = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            return nil
        }

        // Confirm we're looking at an ECDSA key by checking attributes; this
        // catches the case where Apple ever returns a non-ECDSA key from a
        // cert that we expected to be ECDSA.
        guard let attributes = SecKeyCopyAttributes(publicKey) as? [CFString: Any],
              let keyType = attributes[kSecAttrKeyType] as? String,
              keyType == (kSecAttrKeyTypeECSECPrimeRandom as String) else {
            return nil
        }

        // ECDSA P-256 X9.63 uncompressed point is exactly 65 bytes.
        guard raw.count == 65 else { return nil }

        var spki = Data(ecdsaP256SPKIPrefix)
        spki.append(raw)
        return Data(SHA256.hash(data: spki)).base64EncodedString()
    }

    // MARK: - URLSession Delegate

    func urlSession(_ session: URLSession,
                          didReceive challenge: URLAuthenticationChallenge,
                          completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {

        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        guard pinnedHosts.contains(challenge.protectionSpace.host) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        guard let serverTrust = challenge.protectionSpace.serverTrust else {
            logger.warning("No server trust available for \(challenge.protectionSpace.host)")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        if validateCertificateChain(serverTrust: serverTrust) {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            let host = challenge.protectionSpace.host
            logger.error("Certificate pinning validation failed for \(host)")
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    // MARK: - Certificate Validation

    private func validateCertificateChain(serverTrust: SecTrust) -> Bool {
        // 1. Standard X.509 validation (signature, expiry, trust to a system root).
        var error: CFError?
        guard SecTrustEvaluateWithError(serverTrust, &error) else {
            logger.warning("X.509 validation failed: \(error?.localizedDescription ?? "Unknown error")")
            return false
        }

        // 2. Extract the certificate chain. The leaf is at index 0.
        guard let certificateChain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate] else {
            logger.error("Failed to copy certificate chain")
            return false
        }

        // 3. Require the LEAF SPKI hash to match a pinned hash. Matching only an
        //    intermediate or root is no longer sufficient.
        return validateLeafSPKI(certificateChain)
    }
}

// MARK: - Secure URLSession Configuration

extension CertificatePinningManager {

    /// Creates a URLSession with certificate pinning enabled
    func createPinnedURLSession() -> URLSession {
        let configuration = URLSessionConfiguration.default

        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        configuration.tlsMaximumSupportedProtocolVersion = .TLSv13
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        return URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: nil
        )
    }
}

