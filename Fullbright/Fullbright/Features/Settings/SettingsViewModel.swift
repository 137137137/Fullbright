//
//  SettingsViewModel.swift
//  Fullbright
//
//  Settings window view model. Does NOT import AppKit directly — dock
//  visibility goes through an injected protocol.
//

import Foundation
import Sparkle
import os

private let logger = Logger(subsystem: AppIdentifier.serviceID, category: "Settings")

@MainActor
@Observable
final class SettingsViewModel {
    let updaterController: SPUStandardUpdaterController
    private let launchManager: any LaunchAtLoginManaging
    private let defaults: UserDefaults
    private let dockController: any DockVisibilityControlling


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

    init(updaterController: SPUStandardUpdaterController,
         launchManager: any LaunchAtLoginManaging,
         dockController: any DockVisibilityControlling,
         defaults: UserDefaults = .standard) {
        self.updaterController = updaterController
        self.launchManager = launchManager
        self.dockController = dockController
        self.defaults = defaults
    }

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

    // MARK: - Debug Actions

    #if DEBUG
    /// Callback to trigger onboarding flow from settings (DEBUG only).
    var onShowOnboarding: (() -> Void)?

    func showOnboarding() {
        defaults.set(false, forKey: DefaultsKey.hasCompletedOnboarding)
        onShowOnboarding?()
    }
    #endif
}
