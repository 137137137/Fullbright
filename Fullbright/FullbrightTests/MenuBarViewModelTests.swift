//
//  MenuBarViewModelTests.swift
//  FullbrightTests
//

import Foundation
import Sparkle
import Testing
@testable import Fullbright

@MainActor
@Suite("MenuBarViewModel")
struct MenuBarViewModelTests {

    private func makeViewModel(
        xdr: StubXDRController = StubXDRController(),
        auth: StubAuthManager = StubAuthManager(),
        lifecycle: StubAppLifecycle = StubAppLifecycle()
    ) -> (MenuBarViewModel, StubXDRController, StubAuthManager, StubAppLifecycle) {
        // SPUStandardUpdaterController is a concrete Sparkle type we can't
        // easily stub. Construct a real one — it's cheap and doesn't hit
        // the network until checkForUpdates is called.
        let updater = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        let vm = MenuBarViewModel(
            xdrController: xdr,
            authManager: auth,
            updaterController: updater,
            appLifecycle: lifecycle
        )
        return (vm, xdr, auth, lifecycle)
    }

    @Test("quitApp delegates to AppLifecycle.terminate")
    func quitApp_callsLifecycle() {
        let (vm, _, _, lifecycle) = makeViewModel()
        vm.quitApp()
        #expect(lifecycle.terminateCallCount == 1)
    }

    @Test("isXDRSupported reflects the underlying XDRControlling")
    func isXDRSupported_reflectsController() {
        let xdr = StubXDRController()
        xdr.isXDRSupported = true
        let (vm, _, _, _) = makeViewModel(xdr: xdr)
        #expect(vm.isXDRSupported == true)

        xdr.isXDRSupported = false
        #expect(vm.isXDRSupported == false)
    }

    @Test("canUseXDR reflects auth state")
    func canUseXDR_reflectsAuthState() {
        let auth = StubAuthManager()
        auth.authState = .authenticated(licenseKey: "K")
        let (vm, _, _, _) = makeViewModel(auth: auth)
        #expect(vm.canUseXDR == true)

        auth.authState = .expired
        #expect(vm.canUseXDR == false)
    }

    @Test("setXDREnabled(true) enables when canUseXDR is true and not already enabled")
    func setXDREnabled_enablesWhenAllowed() {
        let xdr = StubXDRController()
        let auth = StubAuthManager()
        auth.authState = .authenticated(licenseKey: "K")
        let (vm, _, _, _) = makeViewModel(xdr: xdr, auth: auth)

        vm.setXDREnabled(true)
        #expect(xdr.enableCallCount == 1)
    }

    @Test("setXDREnabled is a no-op when canUseXDR is false")
    func setXDREnabled_noOpWhenNotAllowed() {
        let xdr = StubXDRController()
        let auth = StubAuthManager()
        auth.authState = .expired
        let (vm, _, _, _) = makeViewModel(xdr: xdr, auth: auth)

        vm.setXDREnabled(true)
        #expect(xdr.enableCallCount == 0)
    }

    @Test("setXDREnabled(false) disables XDR when currently enabled")
    func setXDREnabled_false_disablesXDR() {
        let xdr = StubXDRController()
        xdr.isEnabled = true
        let auth = StubAuthManager()
        auth.authState = .authenticated(licenseKey: "K")
        let (vm, _, _, _) = makeViewModel(xdr: xdr, auth: auth)

        vm.setXDREnabled(false)
        #expect(xdr.disableCallCount == 1)
    }

    @Test("refreshAuthIfUnauthenticated refreshes only in notAuthenticated or expired states")
    func refreshAuth_onlyWhenUnauthenticated() {
        let auth = StubAuthManager()
        let (vm, _, _, _) = makeViewModel(auth: auth)

        auth.authState = .notAuthenticated
        vm.refreshAuthIfUnauthenticated()
        #expect(auth.refreshCallCount == 1)

        auth.authState = .expired
        vm.refreshAuthIfUnauthenticated()
        #expect(auth.refreshCallCount == 2)

        auth.authState = .authenticated(licenseKey: "K")
        vm.refreshAuthIfUnauthenticated()
        #expect(auth.refreshCallCount == 2) // unchanged
    }
}
