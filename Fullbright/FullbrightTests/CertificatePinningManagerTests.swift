//
//  CertificatePinningManagerTests.swift
//  FullbrightTests
//
//  Real cert fixture tests for SPKI leaf pinning. The DER bytes below
//  were captured from the live fullbright.app handshake on 2026-04-07
//  and exercise the validator end-to-end without a TLS round trip.
//
//  These tests would have caught the original "any-cert-in-chain wins"
//  bug because they assert specifically that the LEAF must match —
//  matching only the intermediate is no longer sufficient.
//

import Foundation
import Security
import Testing
@testable import Fullbright

// MARK: - Captured cert fixtures (live fullbright.app, 2026-04-07)

private enum CertFixtures {
    /// fullbright.app + www.fullbright.app leaf (ECDSA P-256), issued by LE E7.
    static let leafBase64 = "MIIDlTCCAxqgAwIBAgISBUO3YbDXTiHsWp+Rt7+OTtR+MAoGCCqGSM49BAMDMDIxCzAJBgNVBAYTAlVTMRYwFAYDVQQKEw1MZXQncyBFbmNyeXB0MQswCQYDVQQDEwJFNzAeFw0yNjAzMDYxNzU2MDhaFw0yNjA2MDQxNzU2MDdaMBkxFzAVBgNVBAMTDmZ1bGxicmlnaHQuYXBwMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE+SInbFwb3nmc6SxrtYXL5CiKunC/MkYZNwjOlqsy5GfUgdIY/juMjyV/IxBkOE5ZrujfBMIiuPq7LRtwz/AfzaOCAicwggIjMA4GA1UdDwEB/wQEAwIHgDATBgNVHSUEDDAKBggrBgEFBQcDATAMBgNVHRMBAf8EAjAAMB0GA1UdDgQWBBSTaV1pbEqEzZF9fP1maQ0YHNrzRzAfBgNVHSMEGDAWgBSuSJ7chx1EoG/aouVgdAR4wpwAgDAyBggrBgEFBQcBAQQmMCQwIgYIKwYBBQUHMAKGFmh0dHA6Ly9lNy5pLmxlbmNyLm9yZy8wLQYDVR0RBCYwJIIOZnVsbGJyaWdodC5hcHCCEnd3dy5mdWxsYnJpZ2h0LmFwcDATBgNVHSAEDDAKMAgGBmeBDAECATAuBgNVHR8EJzAlMCOgIaAfhh1odHRwOi8vZTcuYy5sZW5jci5vcmcvMTI3LmNybDCCAQQGCisGAQQB1nkCBAIEgfUEgfIA8AB3AEmcm2neHXzs/DbezYdkprhbrwqHgBnRVVL76esp3fjDAAABnMSAdRoAAAQDAEgwRgIhAO5N0bowQKAMH23ur56cdeVbk35x8Bhwe5UbtSxi208qAiEA43zXtnu+J8DBLVtarxtXgF8nUe+pIcWlS/9QbkRoXf8AdQDRbqmlaAd+ZjWgPzel3bwDpTxBEhTUiBj16TGzI8uVBAAAAZzEgHX7AAAEAwBGMEQCICtcvAOsP/2Jf3s4UWSS2lvnfhPCAIovvkXSVLmFPWZwAiBY+KSBESQxubEv/SBnsMZOP+ig34evGgQbj34sZxbnATAKBggqhkjOPQQDAwNpADBmAjEAo5rCKthRpwHiU7dUSzW4kemzRFzsXbNvfZD9/K89jCQ4PeX6413kp54ZL4FExOxLAjEAh0q42AkOKeEXcp9v3E/okwhR+ZrgJenV5JSKTdgXY9nPovBr+Y5m3GEEUEwoMcFw"

    /// Let's Encrypt E7 intermediate (ECDSA), issued by ISRG Root X1.
    static let intermediateBase64 = "MIIEVzCCAj+gAwIBAgIRAKp18eYrjwoiCWbTi7/UuqEwDQYJKoZIhvcNAQELBQAwTzELMAkGA1UEBhMCVVMxKTAnBgNVBAoTIEludGVybmV0IFNlY3VyaXR5IFJlc2VhcmNoIEdyb3VwMRUwEwYDVQQDEwxJU1JHIFJvb3QgWDEwHhcNMjQwMzEzMDAwMDAwWhcNMjcwMzEyMjM1OTU5WjAyMQswCQYDVQQGEwJVUzEWMBQGA1UEChMNTGV0J3MgRW5jcnlwdDELMAkGA1UEAxMCRTcwdjAQBgcqhkjOPQIBBgUrgQQAIgNiAARB6ASTCFh/vjcwDMCgQer+VtqEkz7JANurZxLP+U9TCeioL6sp5Z8VRvRbYk4P1INBmbefQHJFHCxcSjKmwtvGBWpl/9ra8HW0QDsUaJW2qOJqceJ0ZVFT3hbUHifBM/2jgfgwgfUwDgYDVR0PAQH/BAQDAgGGMB0GA1UdJQQWMBQGCCsGAQUFBwMCBggrBgEFBQcDATASBgNVHRMBAf8ECDAGAQH/AgEAMB0GA1UdDgQWBBSuSJ7chx1EoG/aouVgdAR4wpwAgDAfBgNVHSMEGDAWgBR5tFnme7bl5AFzgAiIyBpY9umbbjAyBggrBgEFBQcBAQQmMCQwIgYIKwYBBQUHMAKGFmh0dHA6Ly94MS5pLmxlbmNyLm9yZy8wEwYDVR0gBAwwCjAIBgZngQwBAgEwJwYDVR0fBCAwHjAcoBqgGIYWaHR0cDovL3gxLmMubGVuY3Iub3JnLzANBgkqhkiG9w0BAQsFAAOCAgEAjx66fDdLk5ywFn3CzA1w1qfylHUDaEf0QZpXcJseddJGSfbUUOvbNR9N/QQ16K1lXl4VFyhmGXDT5Kdfcr0RvIIVrNxFh4lqHtRRCP6RBRstqbZ2zURgqakn/Xip0iaQL0IdfHBZr396FgknniRYFckKORPGyM3QKnd66gtMst8I5nkRQlAg/Jb+Gc3egIvuGKWboE1G89NTsN9LTDD3PLj0dUMrOIuqVjLB8pEC6yk9enrlrqjXQgkLEYhXzq7dLafv5Vkig6Gl0nuuqjqfp0Q1bi1oyVNAlXe6aUXw92CcghC9bNsKEO1+M52YY5+ofIXlS/SEQbvVYYBLZ5yeiglV6t3SM6H+vTG0aP9YHzLn/KVOHzGQfXDP7qM5tkf+7diZe7o2fw6O7IvN6fsQXEQQj8TJUXJxv2/uJhcuy/tSDgXwHM8Uk34WNbRT7zGTGkQRX0gsbjAea/jYAoWv0ZvQRwpqPe79D/i7Cep8qWnA+7AE/3B3S/3dEEYmc0lpe1366A/6GEgk3ktr9PEoQrLChs6Itu3wnNLB2euC8IKGLQFpGtOO/2/hiAKjyajaBP25w1jF0Wl8Bbqne3uZ2q1GyPFJYRmT7/OXpmOH/FVLtwS+8ng1cAmpCujPwteJZNcDG0sF2n/sc0+SQf49fdyUK0ty+VUwFj9tmWxyR/M="

    static func cert(_ base64: String) -> SecCertificate? {
        guard let der = Data(base64Encoded: base64) else { return nil }
        return SecCertificateCreateWithData(nil, der as CFData)
    }
}

@Suite("CertificatePinningManager")
struct CertificatePinningManagerTests {

    @Test("createPinnedURLSession returns a session configured with TLS 1.2+")
    func createPinnedURLSession_configuresTLSFloor() {
        let session = CertificatePinningManager.shared.createPinnedURLSession()
        let config = session.configuration
        #expect(config.tlsMinimumSupportedProtocolVersion == .TLSv12)
        #expect(config.tlsMaximumSupportedProtocolVersion == .TLSv13)
    }

    @Test("pinned session disables cookies and URL cache")
    func createPinnedURLSession_disablesStorage() {
        let session = CertificatePinningManager.shared.createPinnedURLSession()
        let config = session.configuration
        #expect(config.httpShouldSetCookies == false)
        #expect(config.httpCookieAcceptPolicy == .never)
        #expect(config.urlCache == nil)
        #expect(config.requestCachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
    }

    // MARK: - SPKI leaf validation

    @Test("real fullbright.app leaf cert passes leaf SPKI pinning")
    func realLeafCert_passesPinning() throws {
        let leaf = try #require(CertFixtures.cert(CertFixtures.leafBase64))
        let intermediate = try #require(CertFixtures.cert(CertFixtures.intermediateBase64))

        let chain: [SecCertificate] = [leaf, intermediate]
        #expect(CertificatePinningManager.shared.validateLeafSPKI(chain) == true)
    }

    @Test("intermediate-only chain (leaf missing) is rejected")
    func intermediateOnly_isRejected() throws {
        // Simulates the original bug: a chain whose leaf is NOT the pinned cert
        // but whose root or intermediate would have matched under the old logic.
        // Under the fixed logic, this must be rejected.
        let intermediate = try #require(CertFixtures.cert(CertFixtures.intermediateBase64))

        let chain: [SecCertificate] = [intermediate]
        #expect(CertificatePinningManager.shared.validateLeafSPKI(chain) == false)
    }

    @Test("empty chain is rejected")
    func emptyChain_isRejected() {
        #expect(CertificatePinningManager.shared.validateLeafSPKI([]) == false)
    }

    @Test("chain whose leaf is the intermediate (chain order swapped) is rejected")
    func swappedChain_isRejected() throws {
        // If a malicious server presents a chain where the LE intermediate is at
        // index 0 (somehow), it must not match the leaf-only pin.
        let intermediate = try #require(CertFixtures.cert(CertFixtures.intermediateBase64))
        let leaf = try #require(CertFixtures.cert(CertFixtures.leafBase64))

        // intermediate first, leaf second — leaf is no longer at index 0
        let swapped: [SecCertificate] = [intermediate, leaf]
        #expect(CertificatePinningManager.shared.validateLeafSPKI(swapped) == false)
    }
}
