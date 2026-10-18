//
//  AppComposition.swift
//  Fullbright
//
//  THE ONE AND ONLY PLACE where production dependencies are constructed.
//  AppCoordinator used to own the graph through a pile of optional init
//  parameters with `.shared` singleton defaults — that made it a hybrid
//  of composition root and orchestrator. Now:
//
//    • This file decides what the concrete types are.
//    • AppCoordinator just holds the dependencies and reacts to events.
//    • Tests inject their own `AppDependencies` with stub types.
//
//  No other file in the codebase should call `*.init()` on a type that
//  could reasonably be mocked. If you add a new component, construct it
//  here and pass it through.
//

import Foundation
import Sparkle

/// Bag of wired-up dependencies. Expressed as protocol existentials so
/// tests can substitute any field.
@MainActor
struct AppDependencies {
    let xdrController: any XDRControlling
    let keyManager: any BrightnessKeyManaging
    let osdController: any OSDShowing
    let osdEventRouter: any OSDEventRouting
    let updaterController: SPUStandardUpdaterController
    let restoreGammaIfNeeded: @MainActor () -> Void
    let dockController: any DockVisibilityControlling
    let menuBarViewModel: MenuBarViewModel
    let settingsViewModel: SettingsViewModel
}

@MainActor
enum AppComposition {

    /// Builds the production dependency graph. Called once from
    /// `FullbrightApp.init`. Every concrete type in the production build
    /// originates here.
    static func makeDependencies() -> AppDependencies {
        // --- Foundation layer ---
        let dirtyFlagStore: any XDRDirtyFlagStoring = UserDefaultsXDRDirtyFlagStore()

        // --- Display/hardware stack ---
        let displayServices = DisplayServicesClient()
        let nightShift = NightShiftManager()
        let gammaManager = GammaTableManager()
        let displayConfigurator = SkyLightDisplayConfigurator()
        let edrSignal = ScreenEDRSignalProvider()
        let lifecycleObserver = DisplayLifecycleObserver()
        let xdrController: any XDRControlling = XDRController(
            displayServices: displayServices,
            nightShiftManager: nightShift,
            gammaManager: gammaManager,
            displayConfigurator: displayConfigurator,
            dirtyFlagStore: dirtyFlagStore,
            edrSignal: edrSignal,
            lifecycleObserver: lifecycleObserver
        )
        let keyManager: any BrightnessKeyManaging = BrightnessKeyManager()

        // --- UI layer ---
        let osdController = XDRBrightnessOSDWindowController(xdrController: xdrController)
        let osdEventRouter: any OSDEventRouting = OSDEventRouter(
            xdrController: xdrController,
            osdController: osdController
        )

        let updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        // --- AppKit adapters (the ONLY place ViewModels touch AppKit) ---
        let appLifecycle: any AppLifecycle = DefaultAppLifecycle()
        let dockController: any DockVisibilityControlling = DefaultDockVisibilityController()
        let launchManager: any LaunchAtLoginManaging = LaunchAtLoginManager()

        let menuBarViewModel = MenuBarViewModel(
            xdrController: xdrController,
            updaterController: updaterController,
            appLifecycle: appLifecycle
        )
        let settingsViewModel = SettingsViewModel(
            updaterController: updaterController,
            launchManager: launchManager,
            dockController: dockController
        )

        // Capture the shared dirty store so crash recovery runs through
        // the same instance the XDR controller writes to.
        let restoreGammaIfNeeded: @MainActor () -> Void = {
            dirtyFlagStore.restoreIfNeeded()
        }

        return AppDependencies(
            xdrController: xdrController,
            keyManager: keyManager,
            osdController: osdController,
            osdEventRouter: osdEventRouter,
            updaterController: updaterController,
            restoreGammaIfNeeded: restoreGammaIfNeeded,
            dockController: dockController,
            menuBarViewModel: menuBarViewModel,
            settingsViewModel: settingsViewModel
        )
    }
}
