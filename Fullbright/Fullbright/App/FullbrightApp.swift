//
//  FullbrightApp.swift
//  Fullbright
//

import SwiftUI
import Sparkle

@main
struct FullbrightApp: App {
    @State private var coordinator = AppCoordinator()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // Wire coordinator to AppDelegate so lifecycle events route through it
        appDelegate.coordinator = _coordinator.wrappedValue
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(viewModel: coordinator.menuBarViewModel)
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(viewModel: coordinator.settingsViewModel)
                .frame(width: WindowSize.settingsWidth, height: WindowSize.settingsHeight)
                .onAppear {
                    // Workaround: SwiftUI Settings windows don't auto-focus on macOS 13-15.
                    // Uses private window identifier — verified on macOS 13.0–15.0.
                    if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "com.apple.SwiftUI.Settings" }) {
                        window.makeKeyAndOrderFront(nil)
                    }
                }
        }
        .defaultSize(width: WindowSize.settingsWidth, height: WindowSize.settingsHeight)
        .commands {
            CommandGroup(replacing: .appSettings) {
                SettingsLink()
                    .keyboardShortcut(",", modifiers: .command)
            }
        }

        #if DEBUG
        Window("Sparkle Testing", id: "sparkle-testing") {
            SparkleTestingView(updater: coordinator.updaterController.updater)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 500, height: 700)
        #endif
    }
}
