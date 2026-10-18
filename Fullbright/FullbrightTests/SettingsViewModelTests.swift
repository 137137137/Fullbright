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
        dock: StubDockVisibilityController = StubDockVisibilityController(),
        launch: StubLaunchAtLoginManager = StubLaunchAtLoginManager()
    ) -> (SettingsViewModel, StubDockVisibilityController, StubLaunchAtLoginManager) {
        let updater = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        let defaults = UserDefaults(suiteName: "fb-settings-test-\(UUID().uuidString)")!
        let vm = SettingsViewModel(
            updaterController: updater,
            launchManager: launch,
            dockController: dock,
            defaults: defaults
        )
        return (vm, dock, launch)
    }

    @Test("showInDock get returns the dock controller's value")
    func showInDock_getReflectsDockController() {
        let dock = StubDockVisibilityController()
        dock.isVisible = true
        let (vm, _, _) = makeViewModel(dock: dock)
        #expect(vm.showInDock == true)
    }

    @Test("showInDock set forwards to the dock controller")
    func showInDock_setForwardsToDockController() {
        let (vm, dock, _) = makeViewModel()
        vm.showInDock = true
        #expect(dock.isVisible == true)
        vm.showInDock = false
        #expect(dock.isVisible == false)
    }

    @Test("launchAtLogin set delegates to the launch manager")
    func launchAtLogin_setDelegates() {
        let (vm, _, launch) = makeViewModel()
        vm.launchAtLogin = true
        #expect(launch.isEnabled == true)
    }

    @Test("launchAtLogin set swallows launch manager errors without crashing")
    func launchAtLogin_setSwallowsErrors() {
        let launch = StubLaunchAtLoginManager()
        launch.throwOnSet = NSError(domain: "test", code: 1)
        let (vm, _, _) = makeViewModel(launch: launch)
        // Should not crash.
        vm.launchAtLogin = true
        #expect(launch.isEnabled == false)
    }
}
