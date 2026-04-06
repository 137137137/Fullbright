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
    static let apiBase = URL(string: "https://fullbright.app/api")!
    static let purchaseLicense = URL(string: "https://buy.stripe.com/eVqaEXdxH1tg4WcglYfEk00")!
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

