//
//  ViewModelTestDoubles.swift
//  FullbrightTests
//
//  Stubs for the AppKit-adapter protocols so ViewModels can be tested
//  without touching NSApplication/NSWorkspace.
//

import Foundation
import os
@testable import Fullbright

@MainActor
final class StubAppLifecycle: AppLifecycle {
    private(set) var terminateCallCount = 0
    func terminate() { terminateCallCount += 1 }
}

@MainActor
final class StubURLOpener: URLOpening {
    private(set) var openedURLs: [URL] = []
    func open(_ url: URL) { openedURLs.append(url) }
}

@MainActor
final class StubDockVisibilityController: DockVisibilityControlling {
    var isVisible: Bool = false
    private(set) var applyPersistedCallCount = 0
    func applyPersistedPreference() { applyPersistedCallCount += 1 }
}

final class StubLaunchAtLoginManager: LaunchAtLoginManaging, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<(enabled: Bool, throwOnSet: (any Error)?)>(initialState: (false, nil))

    var isEnabled: Bool {
        get { lock.withLock { $0.enabled } }
        set { lock.withLock { $0.enabled = newValue } }
    }

    var throwOnSet: (any Error)? {
        get { lock.withLock { $0.throwOnSet } }
        set { lock.withLock { $0.throwOnSet = newValue } }
    }

    func setEnabled(_ enabled: Bool) throws {
        try lock.withLock { state in
            if let error = state.throwOnSet { throw error }
            state.enabled = enabled
        }
    }
}

@MainActor
final class StubXDRController: XDRControlling {
    var isEnabled: Bool = false
    var brightness: Float = 0.5
    var currentNits: Int = 500
    var isXDRSupported: Bool = true
    var enableCallCount = 0
    var disableCallCount = 0
    var adjustBrightnessCalls: [Float] = []

    @discardableResult
    func enableXDR() -> Bool {
        enableCallCount += 1
        isEnabled = true
        return true
    }

    @discardableResult
    func disableXDR() -> Bool {
        disableCallCount += 1
        isEnabled = false
        return true
    }

    func adjustBrightness(delta: Float) {
        adjustBrightnessCalls.append(delta)
        brightness = max(0, min(1, brightness + delta))
    }
}

@MainActor
final class StubAuthManager: AuthenticationManaging {
    var authState: AuthenticationState = .notAuthenticated
    var startCallCount = 0
    var refreshCallCount = 0
    var startTrialCallCount = 0
    var activateLicenseCalls: [String] = []
    var nextActivationResult: (success: Bool, message: String?) = (true, nil)
    var logoutCallCount = 0

    func start() async { startCallCount += 1 }
    func refreshAuthenticationState() { refreshCallCount += 1 }
    func startTrial() { startTrialCallCount += 1 }

    func activateLicense(licenseKey: String) async -> (success: Bool, message: String?) {
        activateLicenseCalls.append(licenseKey)
        return nextActivationResult
    }

    func logout() { logoutCallCount += 1 }
}
