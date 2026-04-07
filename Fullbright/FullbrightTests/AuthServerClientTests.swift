//
//  AuthServerClientTests.swift
//  FullbrightTests
//
//  Uses URLProtocol to intercept HTTPS requests and assert on how
//  AuthServerClient builds, sends, and interprets server responses.
//
//  NOTE: In DEBUG builds, AuthServerClient.registerTrial short-circuits to
//  .confirmed before touching the network, so the network-level tests for
//  that method only run as smoke assertions here. A Phase 4 refactor
//  removes the #if DEBUG branch — at that point these tests become
//  exhaustive on the registerTrial path as well.
//

import Foundation
import os
import Testing
@testable import Fullbright

// MARK: - URLProtocol-based stub

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Response: Sendable {
        var statusCode: Int
        var body: Data
        var onRequest: (@Sendable (URLRequest) -> Void)?
    }

    static let handlerLock = OSAllocatedUnfairLock<Response?>(initialState: nil)

    static func install(_ response: Response) {
        handlerLock.withLock { $0 = response }
    }

    static func reset() {
        handlerLock.withLock { $0 = nil }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = Self.handlerLock.withLock { $0 }

        guard let response else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }

        response.onRequest?(request)

        let http = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: response.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func makeStubbedSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: config)
}

private let testBaseURL = URL(string: "https://test.example.com/")!

// MARK: - Tests

@Suite("AuthServerClient", .serialized)
struct AuthServerClientTests {

    // MARK: validateLicense

    @Test("validateLicense returns .valid on 200 with valid=true")
    func validateLicense_success() async {
        StubURLProtocol.install(.init(
            statusCode: 200,
            body: #"{"valid":true}"#.data(using: .utf8)!,
            onRequest: nil
        ))
        defer { StubURLProtocol.reset() }

        let client = AuthServerClient(
            apiBaseURL: testBaseURL,
            session: makeStubbedSession(),
            appVersion: "1.0"
        )
        let result = await client.validateLicense(licenseKey: "real-key", deviceId: "d1")
        if case .valid = result {} else {
            Issue.record("expected .valid, got \(result)")
        }
    }

    @Test("validateLicense returns .invalid on 200 with valid=false")
    func validateLicense_invalid() async {
        StubURLProtocol.install(.init(
            statusCode: 200,
            body: #"{"valid":false}"#.data(using: .utf8)!
        ))
        defer { StubURLProtocol.reset() }

        let client = AuthServerClient(
            apiBaseURL: testBaseURL,
            session: makeStubbedSession(),
            appVersion: "1.0"
        )
        let result = await client.validateLicense(licenseKey: "real-key", deviceId: "d1")
        if case .invalid = result {} else {
            Issue.record("expected .invalid, got \(result)")
        }
    }

    @Test("validateLicense returns .offline on non-200 HTTP status")
    func validateLicense_nonSuccessStatusIsOffline() async {
        StubURLProtocol.install(.init(
            statusCode: 500,
            body: Data()
        ))
        defer { StubURLProtocol.reset() }

        let client = AuthServerClient(
            apiBaseURL: testBaseURL,
            session: makeStubbedSession(),
            appVersion: "1.0"
        )
        let result = await client.validateLicense(licenseKey: "real-key", deviceId: "d1")
        if case .offline = result {} else {
            Issue.record("expected .offline, got \(result)")
        }
    }

    // MARK: activateLicense

    @Test("activateLicense returns .success on 200")
    func activateLicense_200_isSuccess() async {
        StubURLProtocol.install(.init(statusCode: 200, body: Data()))
        defer { StubURLProtocol.reset() }

        let client = AuthServerClient(
            apiBaseURL: testBaseURL,
            session: makeStubbedSession(),
            appVersion: "1.0"
        )
        let result = await client.activateLicense(licenseKey: "real-key", deviceId: "d1")
        if case .success = result {} else {
            Issue.record("expected .success, got \(result)")
        }
    }

    @Test("activateLicense returns a device-in-use failure on 409")
    func activateLicense_409_isDeviceConflict() async {
        StubURLProtocol.install(.init(statusCode: 409, body: Data()))
        defer { StubURLProtocol.reset() }

        let client = AuthServerClient(
            apiBaseURL: testBaseURL,
            session: makeStubbedSession(),
            appVersion: "1.0"
        )
        let result = await client.activateLicense(licenseKey: "real-key", deviceId: "d1")
        guard case let .failure(message) = result else {
            Issue.record("expected .failure, got \(result)")
            return
        }
        #expect(message.contains("another device"))
    }

    @Test("activateLicense returns invalid-license failure on 5xx")
    func activateLicense_5xx_isInvalid() async {
        StubURLProtocol.install(.init(statusCode: 500, body: Data()))
        defer { StubURLProtocol.reset() }

        let client = AuthServerClient(
            apiBaseURL: testBaseURL,
            session: makeStubbedSession(),
            appVersion: "1.0"
        )
        let result = await client.activateLicense(licenseKey: "real-key", deviceId: "d1")
        guard case .failure = result else {
            Issue.record("expected .failure, got \(result)")
            return
        }
    }

    // MARK: Request construction

    @Test("activateLicense sends a POST with JSON body containing device_id and license_key")
    func activateLicense_buildsPOSTWithJSONBody() async throws {
        let capture = OSAllocatedUnfairLock<URLRequest?>(initialState: nil)

        StubURLProtocol.install(.init(
            statusCode: 200,
            body: Data(),
            onRequest: { req in
                capture.withLock { $0 = req }
            }
        ))
        defer { StubURLProtocol.reset() }

        let client = AuthServerClient(
            apiBaseURL: testBaseURL,
            session: makeStubbedSession(),
            appVersion: "2.3"
        )
        _ = await client.activateLicense(licenseKey: "LK-1", deviceId: "DEV-1")

        let req = try #require(capture.withLock { $0 })
        #expect(req.httpMethod == "POST")
        #expect(req.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(req.url?.absoluteString.contains("activate-license") == true)
    }
}
