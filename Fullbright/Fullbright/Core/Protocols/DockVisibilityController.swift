//
//  DockVisibilityController.swift
//  Fullbright
//
//  Owns both the UserDefaults-backed persisted preference for "show the
//  app in the Dock" AND the NSApp.setActivationPolicy side effect. Lifted
//  out of AppDelegate and SettingsViewModel so:
//    1. The side effect isn't duplicated between the settings toggle and
//       app launch.
//    2. ViewModels don't touch AppKit directly.
//

import Foundation

@MainActor
protocol DockVisibilityControlling: AnyObject {
    /// The current persisted preference. Reading it returns what's stored
    /// in UserDefaults; writing it both persists AND applies the policy.
    var isVisible: Bool { get set }

    /// Applies the currently-persisted preference. Call at app launch so
    /// the Dock policy matches the user's saved setting before any UI
    /// becomes visible.
    func applyPersistedPreference()
}
