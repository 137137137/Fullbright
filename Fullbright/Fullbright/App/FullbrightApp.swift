//
//  FullbrightApp.swift
//  Fullbright
//

import SwiftUI
import Sparkle

@main
struct FullbrightApp: App {
    @State private var coordinator: AppCoordinator?
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // Unit tests are hosted inside this app target. Building the real
        // dependency graph there would spin up live display/gamma/event-tap
        // I/O and a background EDR-engagement loop that are unrelated to the
        // tests and make runs slow and flaky — so skip composition under test
        // and let the individual XCTest/Swift-Testing suites construct their
        // own subjects with injected doubles.
        guard !Self.isRunningUnitTests else { return }

        // Build the production dependency graph once, in the only place
        // that's allowed to do so, then hand it to the coordinator.
        let dependencies = AppComposition.makeDependencies()
        let coordinator = AppCoordinator(dependencies: dependencies)
        _coordinator = State(initialValue: coordinator)

        // Wire coordinator to AppDelegate so lifecycle events route through it
        appDelegate.coordinator = coordinator
    }

    /// True while the XCTest/Swift-Testing bundle is hosted in this process.
    /// The environment variables are set by the test runner before launch;
    /// the class check alone missed Swift Testing runs (XCTest can load
    /// after `init`), so the real app engaged XDR on the developer's display.
    static var isRunningUnitTests: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["XCTestConfigurationFilePath"] != nil
            || env["XCTestBundlePath"] != nil
            || env["XCTestSessionIdentifier"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    var body: some Scene {
        MenuBarExtra {
            if let coordinator {
                MenuBarContentView(viewModel: coordinator.menuBarViewModel)
            }
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)

        Settings {
            if let coordinator {
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
            if let coordinator {
                SparkleTestingView(updater: coordinator.updaterController.updater)
            }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 500, height: 700)
        #endif
    }
}
