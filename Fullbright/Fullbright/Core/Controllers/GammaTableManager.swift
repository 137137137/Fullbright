//
//  GammaTableManager.swift
//  Fullbright
//
//  Default gamma table and scaled gamma application.
//

import Foundation
import AppKit
import CoreGraphics
import Accelerate
import os

private let logger = Logger(subsystem: AppIdentifier.serviceID, category: "Gamma")

@MainActor
final class GammaTableManager: GammaTableManaging {
    // MARK: - Constants

    private enum Constants {
        static let tableSize: UInt32 = 256
        /// Minimum visible brightness (software brightness floor)
        static let minimumBrightness: Float = 0.08
        /// SDR brightness range (1.0 - minimumBrightness)
        static let sdrRange: Float = 0.92
        /// Timer interval for 60 Hz gamma reapply
        static let timerInterval: TimeInterval = 1.0 / 60.0
        /// Lerp factor per frame for smooth brightness transitions
        static let lerpFactor: Float = 0.3
        /// Convergence threshold below which lerp snaps to target
        static let lerpThreshold: Float = 0.001
    }

    // Default gamma table, read once at init on MainActor then read-only.
    @ObservationIgnored private var defaultGammaRed = [Float](repeating: 0, count: 256)
    @ObservationIgnored private var defaultGammaGreen = [Float](repeating: 0, count: 256)
    @ObservationIgnored private var defaultGammaBlue = [Float](repeating: 0, count: 256)
    @ObservationIgnored private var defaultGammaCount: UInt32 = 0

    private(set) var maxEDR: Float = 1.425738
    private var targetBrightness: Float = 0.0
    private var appliedBrightness: Float = 0.0
    private var hasLoggedScaling = false

    @ObservationIgnored private var renderTask: Task<Void, Never>?

    // MARK: - Read Default Gamma

    func readDefaultGamma(displayID: UInt32) {
        var count: UInt32 = 0
        let err = CGGetDisplayTransferByTable(displayID, Constants.tableSize, &defaultGammaRed, &defaultGammaGreen, &defaultGammaBlue, &count)
        defaultGammaCount = count > 0 ? count : Constants.tableSize

        if err != .success {
            logger.error("CGGetDisplayTransferByTable failed: \(err.rawValue, privacy: .public), using linear fallback")
            setLinearIdentityGamma()
            return
        }

        let sumR = defaultGammaRed.reduce(0, +)
        let sumG = defaultGammaGreen.reduce(0, +)
        let sumB = defaultGammaBlue.reduce(0, +)

        if sumR + sumG + sumB == 0.0 {
            logger.warning("Gamma table is all zeros, using linear identity fallback")
            setLinearIdentityGamma()
            return
        }

        logger.info("Read gamma table: count=\(count, privacy: .public), R[0]=\(self.defaultGammaRed[0], privacy: .public), R[127]=\(self.defaultGammaRed[127], privacy: .public), R[255]=\(self.defaultGammaRed[255], privacy: .public), G[255]=\(self.defaultGammaGreen[255], privacy: .public), B[255]=\(self.defaultGammaBlue[255], privacy: .public)")
    }

    /// Linear identity ramp [0/255, 1/255, ..., 255/255]
    private func setLinearIdentityGamma() {
        defaultGammaCount = Constants.tableSize
        for i in 0..<Int(Constants.tableSize) {
            let v = Float(i) / Float(Constants.tableSize - 1)
            defaultGammaRed[i] = v
            defaultGammaGreen[i] = v
            defaultGammaBlue[i] = v
        }
    }

    // MARK: - Software Brightness

    /// Software brightness for gamma scaling, derived from unified brightness.
    /// Maps: 0.0 -> 0.08 (min visible), 0.5 -> 1.0 (SDR max), 1.0 -> maxEDR (XDR max)
    func softwareBrightness(from brightness: Float) -> Float {
        let boundary = BrightnessNitsConverter.sdrXDRBoundary
        if brightness <= boundary {
            let t = brightness * 2.0
            return Constants.minimumBrightness + t * Constants.sdrRange
        } else {
            let t = (brightness - boundary) * 2.0
            return 1.0 + t * (maxEDR - 1.0)
        }
    }

    // MARK: - Gamma Ramp

    func recomputeMaxEDR() {
        if let screen = NSScreen.main {
            let edr = screen.maximumExtendedDynamicRangeColorComponentValue
            maxEDR = Self.computeMaxEDR(edr: edr)
        }
    }

    func updateBrightness(from unifiedBrightness: Float) {
        // Snap applied to current target first so the lerp doesn't
        // start from a stale intermediate value on rapid key presses
        appliedBrightness = targetBrightness
        targetBrightness = softwareBrightness(from: unifiedBrightness)
    }

    func startSmoothTransition(to target: Float, displayID: UInt32) {
        targetBrightness = target
        appliedBrightness = target
        applyScaledGamma(displayID: displayID, softwareBrightness: appliedBrightness)
        startRenderLoop(displayID: displayID)
    }

    private func startRenderLoop(displayID: UInt32) {
        renderTask?.cancel()
        renderTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Constants.timerInterval))
                guard !Task.isCancelled, let self else { return }
                self.tickRenderLoop(displayID: displayID)
            }
        }
    }

    private func tickRenderLoop(displayID: UInt32) {
        let target = targetBrightness
        let current = appliedBrightness
        if abs(target - current) > Constants.lerpThreshold {
            appliedBrightness = current + (target - current) * Constants.lerpFactor
        } else {
            appliedBrightness = target
        }
        applyScaledGamma(displayID: displayID, softwareBrightness: appliedBrightness)
    }

    func stopRenderLoop() {
        renderTask?.cancel()
        renderTask = nil
    }

    func resetLogging() {
        hasLoggedScaling = false
    }

    // MARK: - Apply Scaled Gamma

    func applyScaledGamma(displayID: UInt32, softwareBrightness: Float? = nil) {
        let count = Int(defaultGammaCount)
        guard count > 0 else { return }

        let sb = softwareBrightness ?? maxEDR
        let brightness = (sb * 100.0).rounded() / 100.0
        let ceiling: Float = brightness > 1.0 ? maxEDR : 1.0
        let t = brightness / ceiling
        let scalingFactor = (ceiling - Constants.minimumBrightness) * t + Constants.minimumBrightness

        if !hasLoggedScaling {
            logger.info("Scaling: maxEDR=\(self.maxEDR, privacy: .public), brightness=\(brightness, privacy: .public), ceiling=\(ceiling, privacy: .public), t=\(t, privacy: .public), scalingFactor=\(scalingFactor, privacy: .public)")
            hasLoggedScaling = true
        }

        var red = [Float](repeating: 0, count: count)
        var green = [Float](repeating: 0, count: count)
        var blue = [Float](repeating: 0, count: count)

        var scale = scalingFactor
        vDSP_vsmul(defaultGammaRed, 1, &scale, &red, 1, vDSP_Length(count))
        vDSP_vsmul(defaultGammaGreen, 1, &scale, &green, 1, vDSP_Length(count))
        vDSP_vsmul(defaultGammaBlue, 1, &scale, &blue, 1, vDSP_Length(count))

        _ = CGSetDisplayTransferByTable(displayID, UInt32(count), red, green, blue)
    }

    // MARK: - Max EDR Polynomial

    /// Max EDR polynomial for mapping EDR headroom to brightness ceiling
    private static func computeMaxEDR(edr: Double) -> Float {
        let rawMax = edr * 0.227317 + 0.899816 + edr * edr * (-0.00590745)
        let capped = max(1.5667381, rawMax)
        return Float(capped + (-0.141))
    }
}
