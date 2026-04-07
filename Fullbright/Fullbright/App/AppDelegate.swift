//
//  AppDelegate.swift
//  Fullbright
//

import AppKit

@MainActor
func setDockVisibility(_ visible: Bool) {
    NSApp.setActivationPolicy(visible ? .regular : .accessory)
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var coordinator: AppCoordinator?
    private var onboardingWindowController: OnboardingWindowController?
    private var signalSources: [any DispatchSourceSignal] = []

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // If gamma was left dirty by a previous crash, restore it now
        coordinator?.restoreStateAfterCrash()

        let showInDock = UserDefaults.standard.bool(forKey: DefaultsKey.showInDock)
        setDockVisibility(showInDock)

        // Wire onboarding callback from settings (DEBUG only)
        #if DEBUG
        coordinator?.settingsViewModel.onShowOnboarding = { [weak self] in
            self?.showOnboarding(isFirstLaunch: false)
        }
        #endif

        if !UserDefaults.standard.bool(forKey: DefaultsKey.hasCompletedOnboarding) {
            showOnboarding()
        }

        installGracefulShutdownHandlers()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.prepareForTermination()
    }

    /// Install signal handlers so gamma is restored on SIGTERM/SIGINT (graceful shutdown).
    /// SIGKILL cannot be caught — the dirty-gamma flag handles that on next launch.
    /// Crash signals (SIGABRT/SIGSEGV/SIGBUS) are NOT handled here because signal
    /// handlers must only call async-signal-safe functions; the dirty-gamma flag
    /// provides crash recovery on next launch via restoreGammaIfNeeded().
    private func installGracefulShutdownHandlers() {
        for sig in [SIGTERM, SIGINT] {
            // Ignore default handler so DispatchSource receives the signal
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                // SAFETY: These are called directly (bypassing AppCoordinator) because
                // the coordinator may already be deallocated when a signal fires.
                // XDRController's static methods and CGDisplayRestoreColorSyncSettings
                // are safe to call from this context.
                CGDisplayRestoreColorSyncSettings()
                UserDefaultsXDRDirtyFlagStore().isDirty = false
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    @MainActor private func showOnboarding(isFirstLaunch: Bool = true) {
        onboardingWindowController?.window?.close()
        onboardingWindowController = OnboardingWindowController(onComplete: { [weak self] in
            UserDefaults.standard.set(true, forKey: DefaultsKey.hasCompletedOnboarding)

            if isFirstLaunch {
                UserDefaults.standard.set(false, forKey: DefaultsKey.showInDock)
                setDockVisibility(false)
            }

            self?.coordinator?.handleOnboardingCompleted()
        })
        onboardingWindowController?.showWindow(nil)
    }
}
