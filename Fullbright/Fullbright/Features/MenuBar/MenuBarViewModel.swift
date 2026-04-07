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

    // MARK: - Actions

    func setXDREnabled(_ enabled: Bool) {
        guard canUseXDR else { return }
        if enabled && !xdrController.isEnabled {
            _ = xdrController.enableXDR()
        } else if !enabled && xdrController.isEnabled {
            _ = xdrController.disableXDR()
        }
    }

    func quitApp() {
        appLifecycle.terminate()
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
