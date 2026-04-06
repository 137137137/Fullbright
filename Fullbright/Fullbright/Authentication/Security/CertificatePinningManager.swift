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
/// (pinnedPublicKeyHashes, pinnedHosts). NSObject base has no mutable state.
/// URLSessionDelegate callbacks execute on URLSession's delegate queue.
final class CertificatePinningManager: NSObject, URLSessionDelegate, @unchecked Sendable {
    static let shared = CertificatePinningManager()

    // Pin the root CA (ISRG Root X1) so renewals and intermediate rotations
    // (E5→E6→E7→E8…) don't break pinning. The root key is stable for years.
    // The current leaf hash is included as an extra check but is not required.
    private let pinnedPublicKeyHashes: Set<String> = [
        // ISRG Root X1 — Let's Encrypt root CA (stable, survives intermediate rotations)
        "C5+lpZ7tcVwmwQIMcRtPbsQtWLABXhQzejna0wHFr8M=",

        // fullbright.app current leaf public key (2025)
        "7ViLqIK5wzSE/uUM1XgRpkS7xJEIGE/f5JW3DTrhSiU="
    ]

    // Hostnames that require certificate pinning
    private let pinnedHosts: Set<String> = [
        "fullbright.app",
        "www.fullbright.app",
        "api.fullbright.app"
    ]

    private override init() {
        super.init()
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
        // Standard X.509 validation first
        var error: CFError?
        guard SecTrustEvaluateWithError(serverTrust, &error) else {
            logger.warning("X.509 validation failed: \(error?.localizedDescription ?? "Unknown error")")
            return false
        }

        guard let certificateChain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate] else {
            return false
        }

        // Check public key hash for each certificate in the chain
        for certificate in certificateChain {
            guard let publicKey = SecCertificateCopyKey(certificate) else { continue }
            if validatePublicKey(publicKey) {
                return true
            }
        }

        return false
    }

    private func validatePublicKey(_ publicKey: SecKey) -> Bool {
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            return false
        }

        let hashString = Data(SHA256.hash(data: publicKeyData)).base64EncodedString()
        return pinnedPublicKeyHashes.contains(hashString)
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

