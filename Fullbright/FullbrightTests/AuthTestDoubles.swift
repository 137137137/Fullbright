//
//  AuthTestDoubles.swift
//  FullbrightTests
//
//  In-memory test doubles for the auth/storage/integrity protocols, so the
//  authentication state machine can be exercised without touching keychain,
//  the filesystem, or the network.
//

import Foundation
import os
@testable import Fullbright

// MARK: - InMemoryKeychain

/// Sendable in-memory keychain replacement. Uses an unfair lock so it can
/// satisfy `KeychainProviding`'s `Sendable` requirement while remaining mutable.
final class InMemoryKeychain: KeychainProviding, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<[String: Data]>(initialState: [:])

    func save(_ data: Data, for key: String) throws {
        lock.withLock { $0[key] = data }
    }

    func load(for key: String) -> Data? {
        lock.withLock { $0[key] }
    }

    func delete(for key: String) throws {
        lock.withLock { _ = $0.removeValue(forKey: key) }
    }
}

// MARK: - InMemorySecureStorage

/// MainActor-isolated in-memory replacement for `SecureFileStorage`.
@MainActor
final class InMemorySecureStorage: SecureStorageProviding {
    private var blobs: [String: Data] = [:]
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func saveEncrypted<T: Codable>(_ object: T, for key: String) throws {
        blobs[key] = try encoder.encode(object)
    }

    func loadEncrypted<T: Codable>(_ type: T.Type, for key: String) -> T? {
        guard let data = blobs[key] else { return nil }
        return try? decoder.decode(type, from: data)
    }

    func delete(for key: String) throws {
        blobs.removeValue(forKey: key)
    }
}

// MARK: - Stubs

struct StubDeviceIdentifier: DeviceIdentifying {
    let secureIdentifier: String
    init(_ id: String = "test-device-id") { self.secureIdentifier = id }
}

struct StubIntegrityChecker: IntegrityChecking {
    let passes: Bool
    init(passes: Bool = true) { self.passes = passes }
    func passesAllChecks() -> Bool { passes }
}

// MARK: - StubAuthServerClient

/// Configurable in-memory replacement for `AuthServerClient`.
final class StubAuthServerClient: AuthServerClientProviding, @unchecked Sendable {
    struct State: Sendable {
        var trialResult: TrialRegistrationResult = .confirmed
        var validationResult: LicenseValidationResult = .valid
        var activationResult: LicenseActivationResult = .success
    }

    private let state: OSAllocatedUnfairLock<State>

    init(_ initial: State = State()) {
        self.state = OSAllocatedUnfairLock(initialState: initial)
    }

    func setTrial(_ result: TrialRegistrationResult) {
        state.withLock { $0.trialResult = result }
    }

    func setValidation(_ result: LicenseValidationResult) {
        state.withLock { $0.validationResult = result }
    }

    func setActivation(_ result: LicenseActivationResult) {
        state.withLock { $0.activationResult = result }
    }

    func registerTrial(deviceId: String) async -> TrialRegistrationResult {
        state.withLock { $0.trialResult }
    }

    func validateLicense(licenseKey: String, deviceId: String) async -> LicenseValidationResult {
        state.withLock { $0.validationResult }
    }

    func activateLicense(licenseKey: String, deviceId: String) async -> LicenseActivationResult {
        state.withLock { $0.activationResult }
    }
}

// MARK: - StubTrialManager / StubLicenseManager
//
// These exist to drive `SecureAuthenticationManager` tests deterministically
// without depending on TrialManager/LicenseManager's async server confirmation.

@MainActor
final class StubTrialManager: TrialManaging {
    var nextCheckResult: AuthenticationState = .notAuthenticated
    var nextStartResult: AuthenticationState = .notAuthenticated
    private(set) var checkCallCount = 0
    private(set) var startCallCount = 0
    var stateChangeHandler: ((AuthenticationState) -> Void)?

    func checkTrialStatus() -> AuthenticationState {
        checkCallCount += 1
        return nextCheckResult
    }

    func startTrial() -> AuthenticationState {
        startCallCount += 1
        return nextStartResult
    }

    func setOnStateChange(_ handler: @escaping @MainActor (AuthenticationState) -> Void) {
        stateChangeHandler = handler
    }

    /// Triggers the registered state-change handler (simulates async server response).
    func emitStateChange(_ state: AuthenticationState) {
        stateChangeHandler?(state)
    }

    #if DEBUG
    func setTrialDaysRemaining(_ days: Int) -> AuthenticationState { nextCheckResult }
    func expireTrial() -> AuthenticationState { .expired }
    func resetTrial() {}
    var trialDuration: Int { 14 }
    func debugTrialInfo() -> String { "" }
    #endif
}

@MainActor
final class StubLicenseManager: LicenseManaging {
    var nextCheckResult: AuthenticationState? = nil
    var nextActivationResult: (success: Bool, message: String?) = (true, nil)
    var nextValidationResult: LicenseValidationResult = .valid
    private(set) var checkCallCount = 0
    private(set) var revokeCallCount = 0
    private(set) var validateBackgroundCallCount = 0
    var stateChangeHandler: ((AuthenticationState) -> Void)?

    func checkLicense() -> AuthenticationState? {
        checkCallCount += 1
        return nextCheckResult
    }

    func setOnStateChange(_ handler: @escaping @MainActor (AuthenticationState) -> Void) {
        stateChangeHandler = handler
    }

    func validateLicenseInBackground(licenseKey: String) {
        validateBackgroundCallCount += 1
    }

    func validateLicense(licenseKey: String) async -> LicenseValidationResult {
        nextValidationResult
    }

    func activateLicense(licenseKey: String) async -> (success: Bool, message: String?) {
        nextActivationResult
    }

    func revokeLicense() {
        revokeCallCount += 1
    }

    /// Triggers the registered state-change handler (simulates async server response).
    func emitStateChange(_ state: AuthenticationState) {
        stateChangeHandler?(state)
    }

    #if DEBUG
    func debugLicenseInfo() -> String { "" }
    func setValidLicense() {}
    #endif
}
