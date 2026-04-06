//
//  AuthServerClientProviding.swift
//  Fullbright
//
//  Server communication protocol.
//

import Foundation

// MARK: - Result Types (shared between protocol and conformers)

enum TrialRegistrationResult: Sendable {
    case confirmed
    case denied
    case offline
}

enum LicenseValidationResult: Sendable {
    case valid
    case invalid
    case offline
}

enum LicenseActivationResult: Sendable {
    case success
    case failure(message: String)
}

// MARK: - Focused Protocols (Interface Segregation)

protocol TrialServerClientProviding: Sendable {
    func registerTrial(deviceId: String) async -> TrialRegistrationResult
}

protocol LicenseValidationClientProviding: Sendable {
    func validateLicense(licenseKey: String, deviceId: String) async -> LicenseValidationResult
}

protocol LicenseActivationClientProviding: Sendable {
    func activateLicense(licenseKey: String, deviceId: String) async -> LicenseActivationResult
}

/// Full server API (all operations).
typealias AuthServerClientProviding = TrialServerClientProviding & LicenseValidationClientProviding & LicenseActivationClientProviding
