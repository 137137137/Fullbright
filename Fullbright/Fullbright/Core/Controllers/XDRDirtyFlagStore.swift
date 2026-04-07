//
//  XDRDirtyFlagStore.swift
//  Fullbright
//
//  Persistent flag that records "the app has modified the display's gamma
//  and has not yet restored it." Used for crash recovery: on next launch,
//  if the flag is set, we call CGDisplayRestoreColorSyncSettings() to undo
//  whatever state a crashed previous run may have left on the display.
//
//  Extracted from XDRController so its UserDefaults access is mockable in
//  tests — and so future persistence-layer changes (e.g. switching to an
//  actor-local file) don't need to touch the controller.
//

import Foundation
import CoreGraphics
import os

private let logger = Logger(subsystem: AppIdentifier.serviceID, category: "XDRDirtyFlag")

@MainActor
protocol XDRDirtyFlagStoring: AnyObject {
    var isDirty: Bool { get set }

    /// Runs gamma restoration if the dirty flag is currently set, then
    /// clears the flag. Safe to call multiple times.
    func restoreIfNeeded()
}

@MainActor
final class UserDefaultsXDRDirtyFlagStore: XDRDirtyFlagStoring {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = DefaultsKey.gammaModified) {
        self.defaults = defaults
        self.key = key
    }

    var isDirty: Bool {
        get { defaults.bool(forKey: key) }
        set { defaults.set(newValue, forKey: key) }
    }

    func restoreIfNeeded() {
        guard isDirty else { return }
        logger.warning("Dirty gamma flag found — restoring ColorSync settings from previous crash")
        CGDisplayRestoreColorSyncSettings()
        isDirty = false
    }
}
