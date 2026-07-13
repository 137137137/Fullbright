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

    func activate() {
        NSApp.activate()
        // The window being opened (e.g. the SwiftUI Settings scene) is
        // created on a later runloop turn — sometimes several — and
        // accessory apps don't get automatic key-window promotion, so
        // without an explicit raise it can sit hidden behind every other
        // app. Poll briefly until it exists, then force it front
        // (orderFrontRegardless works even when macOS denies cooperative
        // activation). The OSD/HDR overlays are panels/borderless and
        // can't become key, so they never match.
        Task { @MainActor in
            for _ in 0..<20 {
                let window = NSApp.windows.first { $0.identifier?.rawValue.contains("Settings") == true }
                    ?? NSApp.windows.first { $0.canBecomeKey && $0.isVisible && !($0 is NSPanel) }
                if let window {
                    window.makeKeyAndOrderFront(nil)
                    window.orderFrontRegardless()
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
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
