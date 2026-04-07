//
//  AppCoordinatorAuthGateTests.swift
//  FullbrightTests
//
//  REGRESSION GATE: verifies that AppCoordinator never enables XDR for a
//  user who is not authorized to use it. Every path that could bypass the
//  paywall is tested here.
//
//  If ANY of these tests start failing, a free user may be able to use
//  XDR. Do not change them lightly — they are the last line of defense
//  between the paywall and the compiler.
//

import Foundation
import Sparkle
import Testing
@testable import Fullbright

@MainActor
private func makeDependencies(
    authState: AuthenticationState = .notAuthenticated,
    xdrSupported: Bool = true
) -> (AppDependencies, StubAuthManager, StubXDRController, StubBrightnessKeyManager) {
    let xdr = StubXDRController()
    xdr.isXDRSupported = xdrSupported
    let keyManager = StubBrightnessKeyManager()
    let auth = StubAuthManager()
    auth.authState = authState

    // The OSD controller is a concrete type that requires an XDRControlling;
    // constructing it doesn't touch AppKit until `show()` is called, which
    // none of these tests do.
    let osdController = XDRBrightnessOSDWindowController(xdrController: xdr)
    let osdEventRouter: any OSDEventRouting = OSDEventRouter(
        xdrController: xdr,
        osdController: osdController
    )
    let authStateObserver: any AuthStateObserving = AuthStateObserver(authManager: auth)

    let updater = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    let dockController = StubDockVisibilityController()
    let lifecycle = StubAppLifecycle()
    let urlOpener = StubURLOpener()
    let launchManager = StubLaunchAtLoginManager()

    let menuBarViewModel = MenuBarViewModel(
        xdrController: xdr,
        authManager: auth,
        updaterController: updater,
        appLifecycle: lifecycle
    )
    let settingsViewModel = SettingsViewModel(
        authManager: auth,
        updaterController: updater,
        launchManager: launchManager,
        dockController: dockController,
        urlOpener: urlOpener
    )

    let deps = AppDependencies(
        xdrController: xdr,
        keyManager: keyManager,
        authManager: auth,
        osdController: osdController,
        authStateObserver: authStateObserver,
        osdEventRouter: osdEventRouter,
        updaterController: updater,
        restoreGammaIfNeeded: {},
        dockController: dockController,
        menuBarViewModel: menuBarViewModel,
        settingsViewModel: settingsViewModel
    )
    return (deps, auth, xdr, keyManager)
}

@MainActor
private func waitUntil(
    _ condition: @MainActor () -> Bool,
    timeout: Duration = .seconds(2)
) async -> Bool {
    let start = ContinuousClock.now
    while ContinuousClock.now - start < timeout {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

@MainActor
@Suite("AppCoordinator — auth gate regression tests", .serialized)
struct AppCoordinatorAuthGateTests {

    // MARK: - Initial state (just constructed, no state change yet)

    @Test("notAuthenticated at init: XDR is never enabled")
    func notAuthenticatedAtInit_xdrNeverEnabled() async throws {
        let (deps, _, xdr, keyManager) = makeDependencies(authState: .notAuthenticated)
        _ = AppCoordinator(dependencies: deps)

        // Give the init Task a chance to run its observer handshake + auth.start.
        try await Task.sleep(for: .milliseconds(80))

        #expect(xdr.enableCallCount == 0)
        #expect(xdr.isEnabled == false)
        #expect(keyManager.intercepting == false)
    }

    @Test("expired at init: XDR is never enabled")
    func expiredAtInit_xdrNeverEnabled() async throws {
        let (deps, _, xdr, keyManager) = makeDependencies(authState: .expired)
        _ = AppCoordinator(dependencies: deps)
        try await Task.sleep(for: .milliseconds(80))

        #expect(xdr.enableCallCount == 0)
        #expect(xdr.isEnabled == false)
        #expect(keyManager.intercepting == false)
    }

    @Test("trial at init: XDR IS enabled for trial users")
    func trialAtInit_xdrEnabled() async {
        let expiry = Date(timeIntervalSinceNow: 86400 * 7)
        let (deps, _, xdr, keyManager) = makeDependencies(
            authState: .trial(daysRemaining: 7, expiryDate: expiry)
        )
        _ = AppCoordinator(dependencies: deps)

        let enabled = await waitUntil { xdr.isEnabled }
        #expect(enabled)
        #expect(xdr.enableCallCount >= 1)
        #expect(keyManager.intercepting == true)
    }

    @Test("authenticated at init: XDR IS enabled for paid users")
    func authenticatedAtInit_xdrEnabled() async {
        let (deps, _, xdr, keyManager) = makeDependencies(
            authState: .authenticated(licenseKey: "PAID")
        )
        _ = AppCoordinator(dependencies: deps)

        let enabled = await waitUntil { xdr.isEnabled }
        #expect(enabled)
        #expect(xdr.enableCallCount >= 1)
        #expect(keyManager.intercepting == true)
    }

    // MARK: - Runtime transitions

    @Test("notAuthenticated → trial: XDR transitions to enabled")
    func transitionToTrial_enablesXDR() async {
        let (deps, auth, xdr, _) = makeDependencies(authState: .notAuthenticated)
        let coordinator = AppCoordinator(dependencies: deps)

        // Wait for the init task's handshake to complete so the observer
        // is registered BEFORE we mutate authState.
        _ = await waitUntil { auth.startCallCount == 1 }

        let expiry = Date(timeIntervalSinceNow: 86400 * 14)
        auth.authState = .trial(daysRemaining: 14, expiryDate: expiry)

        let enabled = await waitUntil { xdr.isEnabled }
        #expect(enabled)

        // Explicit last use keeps the coordinator alive through all awaits.
        _ = coordinator
    }

    @Test("trial → expired: XDR transitions to disabled")
    func transitionFromTrialToExpired_disablesXDR() async {
        let expiry = Date(timeIntervalSinceNow: 86400 * 2)
        let (deps, auth, xdr, keyManager) = makeDependencies(
            authState: .trial(daysRemaining: 2, expiryDate: expiry)
        )
        let coordinator = AppCoordinator(dependencies: deps)

        let enabled = await waitUntil { xdr.isEnabled }
        #expect(enabled, "precondition: XDR should enable at init for a trial user")

        // Wait for the observer's async handshake to complete before mutating.
        _ = await waitUntil { auth.startCallCount == 1 }

        auth.authState = .expired

        // Wait on the disable call count — if this is non-zero then
        // syncXDRState ran, which means the observer fired correctly.
        let disabled = await waitUntil { xdr.disableCallCount >= 1 }
        #expect(disabled, "observer should have fired a disable after transition to .expired")
        #expect(xdr.isEnabled == false)
        #expect(keyManager.intercepting == false)

        _ = coordinator
    }

    @Test("authenticated → expired (license revoked): XDR transitions to disabled")
    func transitionFromAuthenticatedToExpired_disablesXDR() async {
        let (deps, auth, xdr, _) = makeDependencies(
            authState: .authenticated(licenseKey: "PAID")
        )
        let coordinator = AppCoordinator(dependencies: deps)

        let enabled = await waitUntil { xdr.isEnabled }
        #expect(enabled, "precondition: XDR should enable at init for an authenticated user")

        _ = await waitUntil { auth.startCallCount == 1 }

        auth.authState = .expired

        let disabled = await waitUntil { xdr.disableCallCount >= 1 }
        #expect(disabled, "observer should have fired a disable after transition to .expired")
        #expect(xdr.isEnabled == false)

        _ = coordinator
    }

    @Test("notAuthenticated → expired: XDR remains disabled (no flicker)")
    func transitionFromNotAuthToExpired_xdrStaysOff() async throws {
        let (deps, auth, xdr, _) = makeDependencies(authState: .notAuthenticated)
        _ = AppCoordinator(dependencies: deps)
        try await Task.sleep(for: .milliseconds(80))

        auth.authState = .expired
        try await Task.sleep(for: .milliseconds(80))

        #expect(xdr.enableCallCount == 0)
        #expect(xdr.isEnabled == false)
    }

    // MARK: - XDR hardware support gate

    @Test("notAuthenticated AND hardware unsupported: XDR never enables")
    func notAuthAndUnsupported_xdrNeverEnables() async throws {
        let (deps, _, xdr, _) = makeDependencies(
            authState: .notAuthenticated,
            xdrSupported: false
        )
        _ = AppCoordinator(dependencies: deps)
        try await Task.sleep(for: .milliseconds(80))

        #expect(xdr.enableCallCount == 0)
    }

    @Test("trial user on hardware without XDR support: XDR does not enable")
    func trialButUnsupportedHardware_xdrNeverEnables() async throws {
        let expiry = Date(timeIntervalSinceNow: 86400 * 7)
        let (deps, _, xdr, _) = makeDependencies(
            authState: .trial(daysRemaining: 7, expiryDate: expiry),
            xdrSupported: false
        )
        _ = AppCoordinator(dependencies: deps)
        try await Task.sleep(for: .milliseconds(80))

        #expect(xdr.enableCallCount == 0)
    }
}
