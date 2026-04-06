//
//  SettingsViewModel.swift
//  Fullbright
//
//  Settings window view model.
//

import AppKit
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
    private let dockVisibilitySetter: @MainActor (Bool) -> Void

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
        get { defaults.bool(forKey: DefaultsKey.showInDock) }
        set {
            defaults.set(newValue, forKey: DefaultsKey.showInDock)
            dockVisibilitySetter(newValue)
        }
    }

    struct AlertInfo: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    init(authManager: any AuthenticationManaging,
         updaterController: SPUStandardUpdaterController,
         launchManager: any LaunchAtLoginManaging = LaunchAtLoginManager(),
         defaults: UserDefaults = .standard,
         dockVisibilitySetter: @escaping @MainActor (Bool) -> Void = setDockVisibility) {
        self.authManager = authManager
        self.updaterController = updaterController
        self.launchManager = launchManager
        self.defaults = defaults
        self.dockVisibilitySetter = dockVisibilitySetter
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
        NSWorkspace.shared.open(AppURL.purchaseLicense)
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
