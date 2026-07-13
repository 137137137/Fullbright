//
//  GammaTableManaging.swift
//  Fullbright
//
//  Gamma table management protocol.
//

import Foundation

@MainActor
protocol GammaTableManaging: AnyObject {
    var maxEDR: Float { get }
    var displayPeakNits: Float { get }

    /// Fired after repeated gamma-table drift where our writes stop
    /// sticking (another app fighting over gamma, or a macOS regression
    /// where CGSetDisplayTransferByTable silently no-ops). The policy
    /// layer decides how to react (e.g. disable XDR).
    var onPersistentGammaConflict: (@MainActor () -> Void)? { get set }

    func readDefaultGamma(displayID: UInt32)

    /// Feed the current and potential EDR headroom readings (from
    /// NSScreen) into the brightness-ceiling computation.
    func updateEDRHeadroom(current: Double, potential: Double)

    func softwareBrightness(from brightness: Float) -> Float
    func applyScaledGamma(displayID: UInt32, softwareBrightness: Float?)

    /// Smoothly fade the applied gamma scale to `target` over `duration`
    /// seconds (smoothstep easing). A duration of 0 applies immediately.
    /// Starting a new fade retargets from the currently applied value.
    func fadeToSoftwareBrightness(_ target: Float, displayID: UInt32, duration: TimeInterval)

    /// Start the periodic read-back drift check. Reapplies the expected
    /// table when another writer clobbers it and escalates to
    /// `onPersistentGammaConflict` after repeated consecutive fights.
    func startIntegrityMonitoring(displayID: UInt32)

    /// Cancels any in-flight fade and the integrity monitor.
    func stopGammaActivity()

    func resetLogging()
}
