//
//  OSDEventRouter.swift
//  Fullbright
//
//  Wires brightness-key events from BrightnessKeyManaging into the XDR
//  controller and the OSD window. Extracted from AppCoordinator so:
//    1. AppCoordinator no longer mixes hardware input routing with auth
//       state orchestration.
//    2. The keyDown → adjustBrightness → show OSD pipeline can be tested
//       in isolation with stubbed dependencies.
//

import Foundation
import os

@MainActor
protocol OSDEventRouting: AnyObject {
    /// Installs the brightness-key callback on `keyManager`. Replaces any
    /// previous callback. Calling `attach` with a new key manager detaches
    /// the previous one first.
    func attach(to keyManager: any BrightnessKeyManaging)

    /// Removes the brightness-key callback from the currently-attached
    /// manager, if any.
    func detach()
}

@MainActor
final class OSDEventRouter: OSDEventRouting {
    private let xdrController: any XDRControlling
    private let osdController: any OSDShowing
    private weak var currentKeyManager: (any BrightnessKeyManaging)?

    init(xdrController: any XDRControlling,
         osdController: any OSDShowing) {
        self.xdrController = xdrController
        self.osdController = osdController
    }

    func attach(to keyManager: any BrightnessKeyManaging) {
        // Detach from any prior manager to avoid dangling callbacks.
        detach()

        // Capture the step up-front so the event-tap callback (which
        // runs off the main actor) never has to touch any actor-isolated
        // state to determine the delta.
        let step = keyManager.brightnessStep
        keyManager.onBrightnessKey = { [weak self] isUp in
            guard let self else { return }
            self.xdrController.adjustBrightness(delta: isUp ? step : -step)
            self.osdController.show()
        }
        currentKeyManager = keyManager
    }

    func detach() {
        currentKeyManager?.onBrightnessKey = nil
        currentKeyManager = nil
    }
}
