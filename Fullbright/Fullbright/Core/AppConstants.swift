//
//  AppConstants.swift
//  Fullbright
//
//  App-wide constants.
//

import Foundation

// MARK: - UserDefaults Keys

enum DefaultsKey {
    static let hasCompletedOnboarding = "fullbright.hasCompletedOnboarding"
    static let showInDock = "fullbright.showInDock"
    static let gammaModified = "fullbright.gammaModified"
}

// MARK: - App Identifiers

enum AppIdentifier {
    /// Namespace identifier used for logging.
    static let serviceID = "com.fullbright.app"
}

// MARK: - URLs

enum AppURL {
    static let sparkleTesting = Self.requireURL("fullbright://sparkle-testing")

    /// Force-unwraps a URL string literal with a clear failure message.
    /// Only used for compile-time-known constants; any runtime URL
    /// parsing should use `URL(string:)` and handle nil explicitly.
    private static func requireURL(_ string: String, file: StaticString = #file, line: UInt = #line) -> URL {
        guard let url = URL(string: string) else {
            fatalError("AppURL: failed to parse compile-time URL literal '\(string)'", file: file, line: line)
        }
        return url
    }
}

// MARK: - Notifications

extension Notification.Name {
    /// Posted when XDR is force-disabled because gamma writes repeatedly
    /// failed to stick (another gamma app, or a broken macOS gamma API).
    static let fullbrightGammaConflict = Notification.Name("fullbright.gammaConflict")
}

// MARK: - Window Dimensions

enum WindowSize {
    static let settingsWidth: CGFloat = 600
    static let settingsHeight: CGFloat = 450
}

