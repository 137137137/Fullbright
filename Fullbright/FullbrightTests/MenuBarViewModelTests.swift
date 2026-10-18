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
        lifecycle: StubAppLifecycle = StubAppLifecycle()
    ) -> (MenuBarViewModel, StubXDRController, StubAppLifecycle) {
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
            updaterController: updater,
            appLifecycle: lifecycle
        )
        return (vm, xdr, lifecycle)
    }

    @Test("quitApp delegates to AppLifecycle.terminate")
    func quitApp_callsLifecycle() {
        let (vm, _, lifecycle) = makeViewModel()
        vm.quitApp()
        #expect(lifecycle.terminateCallCount == 1)
    }

    @Test("activateApp delegates to AppLifecycle.activate")
    func activateApp_callsLifecycle() {
        let (vm, _, lifecycle) = makeViewModel()
        vm.activateApp()
        #expect(lifecycle.activateCallCount == 1)
    }

    @Test("isXDRSupported reflects the underlying XDRControlling")
    func isXDRSupported_reflectsController() {
        let xdr = StubXDRController()
        xdr.isXDRSupported = true
        let (vm, _, _) = makeViewModel(xdr: xdr)
        #expect(vm.isXDRSupported == true)

        xdr.isXDRSupported = false
        #expect(vm.isXDRSupported == false)
    }

    @Test("setXDREnabled(true) enables when not already enabled")
    func setXDREnabled_enablesWhenAllowed() {
        let xdr = StubXDRController()
        let (vm, _, _) = makeViewModel(xdr: xdr)

        vm.setXDREnabled(true)
        #expect(xdr.enableCallCount == 1)
    }

    @Test("setXDRBrightness forwards the delta")
    func setXDRBrightness_forwardsWhenAllowed() {
        let xdr = StubXDRController()
        xdr.isEnabled = true
        xdr.brightness = 0.5
        let (vm, _, _) = makeViewModel(xdr: xdr)

        vm.setXDRBrightness(0.8)
        #expect(xdr.adjustBrightnessCalls.count == 1)
        #expect(abs((xdr.adjustBrightnessCalls.first ?? 0) - 0.3) < 0.0001)
    }

    @Test("xdrBrightness and currentNits mirror the controller")
    func brightnessAndNits_mirrorController() {
        let xdr = StubXDRController()
        xdr.brightness = 0.75
        xdr.currentNits = 1050
        let (vm, _, _) = makeViewModel(xdr: xdr)
        #expect(vm.xdrBrightness == 0.75)
        #expect(vm.currentNits == 1050)
    }

    @Test("setXDREnabled(false) disables XDR when currently enabled")
    func setXDREnabled_false_disablesXDR() {
        let xdr = StubXDRController()
        xdr.isEnabled = true
        let (vm, _, _) = makeViewModel(xdr: xdr)

        vm.setXDREnabled(false)
        #expect(xdr.disableCallCount == 1)
    }
}
