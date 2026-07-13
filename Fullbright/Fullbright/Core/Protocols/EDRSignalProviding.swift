//
//  EDRSignalProviding.swift
//  Fullbright
//
//  Read-only view of the display's EDR headroom, abstracted from NSScreen
//  so XDRController's engage/monitor state machine is unit-testable.
//

import Foundation

@MainActor
protocol EDRSignalProviding {
    /// Currently granted EDR headroom (1.0 = none granted yet).
    /// Mirrors `NSScreen.maximumExtendedDynamicRangeColorComponentValue`.
    func currentHeadroom(displayID: UInt32) -> Double

    /// Maximum potential EDR headroom the panel can reach.
    /// Mirrors `NSScreen.maximumPotentialExtendedDynamicRangeColorComponentValue`.
    func potentialHeadroom(displayID: UInt32) -> Double
}
