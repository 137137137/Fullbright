//
//  SettingsViewModel.swift
//  Fullbright
//
//  Settings window view model. Does NOT import AppKit directly — dock
//  visibility and URL opening both go through injected protocols.
//

import Foundation
import Sparkle
import os

private let logger = Logger(subsystem: AppIdentifier.serviceID, category: "Settings")

@MainActor
@Observable
final class SettingsViewModel {
    private let authManager: any AuthenticationManaging
    let updaterController: SPUStandardUpdaterController
    private let launchManager: any LaunchAtLoginManaging
    private let defaults: UserDefaults
    private let dockController: any DockVisibilityControlling
    private let urlOpener: any URLOpening

    var licenseKey = ""
    private(set) var isActivating = false
    var alertState: AlertInfo?

    var launchAtLogin: Bool {
        get { launchManager.isEnabled }
        set {
            do {
                try launchManager.setEnabled(newValue)
            } catch {
                logger.error("Failed to set launch at login: \(error, privacy: .public)")
            }
        }
    }

    var showInDock: Bool {
        get { dockController.isVisible }
        set { dockController.isVisible = newValue }
    }

    struct AlertInfo: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    init(authManager: any AuthenticationManaging,
         updaterController: SPUStandardUpdaterController,
         launchManager: any LaunchAtLoginManaging,
         dockController: any DockVisibilityControlling,
         urlOpener: any URLOpening,
         defaults: UserDefaults = .standard) {
        self.authManager = authManager
        self.updaterController = updaterController
        self.launchManager = launchManager
        self.dockController = dockController
        self.urlOpener = urlOpener
        self.defaults = defaults
        #if DEBUG
        self.debugActions = DebugAuthActions(authManager: authManager)
        #endif
    }

    // MARK: - Computed State

    var authState: AuthenticationState { authManager.authState }
    var isAuthenticated: Bool { authState.isAuthenticated }

    // MARK: - Updater Bindings

    var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set { updaterController.updater.automaticallyChecksForUpdates = newValue }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { updaterController.updater.automaticallyDownloadsUpdates }
        set { updaterController.updater.automaticallyDownloadsUpdates = newValue }
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    // MARK: - License Actions

    func activateLicense() async {
        isActivating = true
        let (success, message) = await authManager.activateLicense(licenseKey: licenseKey)
        isActivating = false

        if success {
            alertState = AlertInfo(
                title: "Success",
                message: "Your license has been successfully activated!"
            )
            licenseKey = ""
        } else {
            alertState = AlertInfo(
                title: "Activation Failed",
                message: message ?? "Invalid License. Please check your license key and try again."
            )
        }
    }

    func purchaseLicense() {
        urlOpener.open(AppURL.purchaseLicense)
    }

    // MARK: - Debug Actions

    #if DEBUG
    let debugActions: DebugAuthActions

    /// Callback to trigger onboarding flow from settings (DEBUG only).
    var onShowOnboarding: (() -> Void)?

    func showOnboarding() {
        defaults.set(false, forKey: DefaultsKey.hasCompletedOnboarding)
        onShowOnboarding?()
    }
    #endif
}
