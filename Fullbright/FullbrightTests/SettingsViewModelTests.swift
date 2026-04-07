//
//  SettingsViewModelTests.swift
//  FullbrightTests
//

import Foundation
import Sparkle
import Testing
@testable import Fullbright

@MainActor
@Suite("SettingsViewModel")
struct SettingsViewModelTests {

    private func makeViewModel(
        auth: StubAuthManager = StubAuthManager(),
        dock: StubDockVisibilityController = StubDockVisibilityController(),
        urlOpener: StubURLOpener = StubURLOpener(),
        launch: StubLaunchAtLoginManager = StubLaunchAtLoginManager()
    ) -> (SettingsViewModel, StubAuthManager, StubDockVisibilityController, StubURLOpener, StubLaunchAtLoginManager) {
        let updater = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        let defaults = UserDefaults(suiteName: "fb-settings-test-\(UUID().uuidString)")!
        let vm = SettingsViewModel(
            authManager: auth,
            updaterController: updater,
            launchManager: launch,
            dockController: dock,
            urlOpener: urlOpener,
            defaults: defaults
        )
        return (vm, auth, dock, urlOpener, launch)
    }

    @Test("purchaseLicense opens the purchase URL via the injected opener")
    func purchaseLicense_opensPurchaseURL() {
        let (vm, _, _, opener, _) = makeViewModel()
        vm.purchaseLicense()
        #expect(opener.openedURLs.count == 1)
        #expect(opener.openedURLs.first == AppURL.purchaseLicense)
    }

    @Test("showInDock get returns the dock controller's value")
    func showInDock_getReflectsDockController() {
        let dock = StubDockVisibilityController()
        dock.isVisible = true
        let (vm, _, _, _, _) = makeViewModel(dock: dock)
        #expect(vm.showInDock == true)
    }

    @Test("showInDock set forwards to the dock controller")
    func showInDock_setForwardsToDockController() {
        let (vm, _, dock, _, _) = makeViewModel()
        vm.showInDock = true
        #expect(dock.isVisible == true)
        vm.showInDock = false
        #expect(dock.isVisible == false)
    }

    @Test("launchAtLogin set delegates to the launch manager")
    func launchAtLogin_setDelegates() {
        let (vm, _, _, _, launch) = makeViewModel()
        vm.launchAtLogin = true
        #expect(launch.isEnabled == true)
    }

    @Test("launchAtLogin set swallows launch manager errors without crashing")
    func launchAtLogin_setSwallowsErrors() {
        let launch = StubLaunchAtLoginManager()
        launch.throwOnSet = NSError(domain: "test", code: 1)
        let (vm, _, _, _, _) = makeViewModel(launch: launch)
        // Should not crash.
        vm.launchAtLogin = true
        #expect(launch.isEnabled == false)
    }

    @Test("activateLicense on success clears the license key field and sets the alert")
    func activateLicense_success() async {
        let auth = StubAuthManager()
        auth.nextActivationResult = (true, nil)
        let (vm, _, _, _, _) = makeViewModel(auth: auth)
        vm.licenseKey = "SOME-KEY-123"
        await vm.activateLicense()
        #expect(vm.licenseKey == "")
        #expect(vm.alertState?.title == "Success")
    }

    @Test("activateLicense on failure keeps the license key and shows a failure alert")
    func activateLicense_failure() async {
        let auth = StubAuthManager()
        auth.nextActivationResult = (false, "Invalid key")
        let (vm, _, _, _, _) = makeViewModel(auth: auth)
        vm.licenseKey = "BAD-KEY"
        await vm.activateLicense()
        #expect(vm.licenseKey == "BAD-KEY")
        #expect(vm.alertState?.title == "Activation Failed")
        #expect(vm.alertState?.message == "Invalid key")
    }
}
