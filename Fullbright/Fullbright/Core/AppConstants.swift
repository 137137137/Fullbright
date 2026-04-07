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
    /// Service/namespace identifier used for keychain, encrypted storage, logging, and device fingerprinting.
    static let serviceID = "com.fullbright.app"
    /// Expected bundle identifier for integrity verification.
    static let expectedBundleIdentifier = "ideals.Fullbright"
}

// MARK: - Encrypted Storage Keys

enum StorageKey {
    static let trialData = "fb.trial.data"
    static let licenseData = "fb.license.data"
    static let trialUsed = "fb.tu"
    static let encryptionSalt = "fb.enc.salt"
}

// MARK: - URLs

enum AppURL {
    static let apiBase = Self.requireURL("https://fullbright.app/api")
    static let purchaseLicense = Self.requireURL("https://buy.stripe.com/eVqaEXdxH1tg4WcglYfEk00")
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

// MARK: - Debug Constants

#if DEBUG
enum DebugConstants {
    static let testLicenseKey = "TEST-TEST-TEST-TEST"
}
#endif

// MARK: - Window Dimensions

enum WindowSize {
    static let settingsWidth: CGFloat = 600
    static let settingsHeight: CGFloat = 450
}

