//
//  ScreenEDRSignalProvider.swift
//  Fullbright
//
//  NSScreen-backed EDR headroom readings.
//

import AppKit

@MainActor
final class ScreenEDRSignalProvider: EDRSignalProviding {
    private func screen(for displayID: UInt32) -> NSScreen? {
        let match = NSScreen.screens.first { screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            return number == displayID
        }
        return match ?? NSScreen.main
    }

    func currentHeadroom(displayID: UInt32) -> Double {
        guard let screen = screen(for: displayID) else { return 1.0 }
        return Double(screen.maximumExtendedDynamicRangeColorComponentValue)
    }

    func potentialHeadroom(displayID: UInt32) -> Double {
        guard let screen = screen(for: displayID) else { return 1.0 }
        return Double(screen.maximumPotentialExtendedDynamicRangeColorComponentValue)
    }
}
