//
//  MenuBarViewModel.swift
//  Fullbright
//
//  Menu bar popover view model. Does NOT import AppKit directly — all
//  platform interaction goes through the AppLifecycle protocol so this
//  file can be tested with stubs and the layering boundary between
//  ViewModel and platform is explicit.
//

import Foundation
import Sparkle

@MainActor
@Observable
final class MenuBarViewModel {
    private let xdrController: any XDRControlling
    private let authManager: any AuthenticationManaging
    private let appLifecycle: any AppLifecycle
    let updaterController: SPUStandardUpdaterController

    init(xdrController: any XDRControlling,
         authManager: any AuthenticationManaging,
         updaterController: SPUStandardUpdaterController,
         appLifecycle: any AppLifecycle) {
        self.xdrController = xdrController
        self.authManager = authManager
        self.updaterController = updaterController
        self.appLifecycle = appLifecycle
        #if DEBUG
        self.debugActions = DebugAuthActions(authManager: authManager)
        #endif
    }

    // MARK: - Computed State

    var isXDRSupported: Bool { xdrController.isXDRSupported }
    var isXDREnabled: Bool { xdrController.isEnabled }
    var canUseXDR: Bool { authManager.authState.canUseXDR }
    var authState: AuthenticationState { authManager.authState }
    /// Unified brightness (0 = min, 0.5 = SDR max, 1 = XDR peak).
    var xdrBrightness: Float { xdrController.brightness }
    var currentNits: Int { xdrController.currentNits }

    // MARK: - Actions

    func setXDREnabled(_ enabled: Bool) {
        guard canUseXDR else { return }
        if enabled && !xdrController.isEnabled {
            _ = xdrController.enableXDR()
        } else if !enabled && xdrController.isEnabled {
            _ = xdrController.disableXDR()
        }
    }

    /// Slider entry point. Gated on auth (active trial or license) — the
    /// same gate as the XDR toggle — and a no-op while XDR is off.
    func setXDRBrightness(_ value: Float) {
        guard canUseXDR else { return }
        xdrController.adjustBrightness(delta: value - xdrController.brightness)
    }

    func quitApp() {
        appLifecycle.terminate()
    }

    /// Bring the app (and whatever window was just opened) to the front.
    /// Required for windows opened from the menu bar — accessory apps
    /// otherwise open them behind the active app.
    func activateApp() {
        appLifecycle.activate()
    }

    func refreshAuthIfUnauthenticated() {
        switch authManager.authState {
        case .notAuthenticated, .expired:
            authManager.refreshAuthenticationState()
        case .authenticated, .trial:
            break
        }
    }

    // MARK: - Debug Actions

    #if DEBUG
    let debugActions: DebugAuthActions
    #endif
}
