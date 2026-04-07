//
//  DefaultAppKitAdapters.swift
//  Fullbright
//
//  Production implementations of AppLifecycle, URLOpening, and
//  DockVisibilityControlling. Kept in the App layer because these are
//  the only types in the main target that are ALLOWED to import AppKit
//  on behalf of the rest of the codebase.
//

import Foundation
import AppKit

@MainActor
struct DefaultAppLifecycle: AppLifecycle {
    func terminate() {
        NSApplication.shared.terminate(nil)
    }
}

@MainActor
struct DefaultURLOpener: URLOpening {
    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}

@MainActor
final class DefaultDockVisibilityController: DockVisibilityControlling {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = DefaultsKey.showInDock) {
        self.defaults = defaults
        self.key = key
    }

    var isVisible: Bool {
        get { defaults.bool(forKey: key) }
        set {
            defaults.set(newValue, forKey: key)
            NSApp.setActivationPolicy(newValue ? .regular : .accessory)
        }
    }

    func applyPersistedPreference() {
        NSApp.setActivationPolicy(isVisible ? .regular : .accessory)
    }
}
