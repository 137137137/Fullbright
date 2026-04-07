//
//  AuthServerClient.swift
//  Fullbright
//
//  Server communication for trial registration, license validation, and activation.
//

import Foundation

final class AuthServerClient: AuthServerClientProviding, Sendable {

    // MARK: - Codable Request/Response Types

    private struct APIRequest: Encodable {
        let deviceId: String
        var licenseKey: String?
        let appVersion: String

        enum CodingKeys: String, CodingKey {
            case deviceId = "device_id"
            case licenseKey = "license_key"
            case appVersion = "app_version"
        }
    }

    private struct ValidationResponse: Decodable {
        let valid: Bool
    }

    // MARK: - Configuration

    private let apiBaseURL: URL
    private let secureSession: URLSession
    private let appVersion: String
    private let encoder = JSONEncoder()

    /// Constructs the client. The `session` parameter is required so callers
    /// (the composition root in production, tests in unit tests) make an explicit
    /// choice about TLS pinning rather than reaching into a singleton from `init`.
    init(apiBaseURL: URL = AppURL.apiBase,
         session: URLSession,
         appVersion: String = Bundle.main.appVersion) {
        self.apiBaseURL = apiBaseURL
        self.secureSession = session
        self.appVersion = appVersion
    }

    // MARK: - Request Building

    private func makeRequest(to path: String, body: APIRequest) throws -> URLRequest {
        let httpBody = try encoder.encode(body)
        let url = apiBaseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = httpBody
        return request
    }

    // MARK: - Trial Registration

    func registerTrial(deviceId: String) async -> TrialRegistrationResult {
        #if DEBUG
        return .confirmed
        #else
        guard let request = try? makeRequest(to: "register-trial", body: APIRequest(deviceId: deviceId, appVersion: appVersion)) else {
            return .offline
        }

        do {
            let (_, response) = try await secureSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return .offline }

            switch httpResponse.statusCode {
            case 200: return .confirmed
            case 409: return .denied
            default: return .offline  // 5xx and other errors should not revoke trials
            }
        } catch {
            return .offline
        }
        #endif
    }

    // MARK: - License Validation

    func validateLicense(licenseKey: String, deviceId: String) async -> LicenseValidationResult {
        #if DEBUG
        if licenseKey == DebugConstants.testLicenseKey {
            return .valid
        }
        #endif

        guard let request = try? makeRequest(
            to: "validate-license",
            body: APIRequest(deviceId: deviceId, licenseKey: licenseKey, appVersion: appVersion)
        ) else {
            return .offline
        }

        do {
            let (data, response) = try await secureSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return .offline
            }
            let decoded = try JSONDecoder().decode(ValidationResponse.self, from: data)
            return decoded.valid ? .valid : .invalid
        } catch {
            return .offline
        }
    }

    // MARK: - License Activation

    func activateLicense(licenseKey: String, deviceId: String) async -> LicenseActivationResult {
        #if DEBUG
        if licenseKey == DebugConstants.testLicenseKey {
            return .success
        }
        #endif

        guard let request = try? makeRequest(
            to: "activate-license",
            body: APIRequest(deviceId: deviceId, licenseKey: licenseKey, appVersion: appVersion)
        ) else {
            return .failure(message: "Unable to connect. Please try again.")
        }

        do {
            let (_, response) = try await secureSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(message: "Unable to connect. Please check your internet connection.")
            }

            switch httpResponse.statusCode {
            case 200:
                return .success
            case 409:
                return .failure(message: "License already in use on another device")
            default:
                return .failure(message: "Invalid License")
            }
        } catch {
            return .failure(message: "Unable to connect. Please check your internet connection.")
        }
    }
}
