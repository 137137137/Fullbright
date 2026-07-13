//
//  GammaTableManager.swift
//  Fullbright
//
//  Default gamma table capture and scaled gamma application.
//
//  Brightness changes are applied as finite smoothstep fades (~0.35s)
//  instead of a permanent 60 Hz reapply loop, and a low-frequency
//  integrity monitor (2s) detects external writers via read-back
//  comparison — reapplying on drift and escalating to
//  `onPersistentGammaConflict` when writes repeatedly fail to stick
//  (another gamma app, or a macOS regression where
//  CGSetDisplayTransferByTable silently no-ops, as happened in the
//  macOS 26 Tahoe betas).
//

import Foundation
import AppKit
import CoreGraphics
import Accelerate
import os

private let logger = Logger(subsystem: AppIdentifier.serviceID, category: "Gamma")

// MARK: - Gamma Table I/O

/// The three CoreGraphics touch-points the manager needs, injectable so
/// fades, baseline capture, and drift detection are testable against a
/// fake table store.
struct GammaTableIO {
    var readTable: @MainActor (_ displayID: UInt32, _ capacity: UInt32)
        -> (red: [Float], green: [Float], blue: [Float], sampleCount: UInt32, error: CGError)
    var writeTable: @MainActor (_ displayID: UInt32, _ red: [Float], _ green: [Float], _ blue: [Float]) -> CGError
    var restoreColorSync: @MainActor () -> Void

    @MainActor static var live: GammaTableIO {
        GammaTableIO(
            readTable: { displayID, capacity in
                var red = [Float](repeating: 0, count: Int(capacity))
                var green = [Float](repeating: 0, count: Int(capacity))
                var blue = [Float](repeating: 0, count: Int(capacity))
                var count: UInt32 = 0
                let err = CGGetDisplayTransferByTable(displayID, capacity, &red, &green, &blue, &count)
                return (red, green, blue, count, err)
            },
            writeTable: { displayID, red, green, blue in
                CGSetDisplayTransferByTable(displayID, UInt32(red.count), red, green, blue)
            },
            restoreColorSync: {
                CGDisplayRestoreColorSyncSettings()
            }
        )
    }
}

// MARK: - GammaTableManager

@MainActor
final class GammaTableManager: GammaTableManaging {
    // MARK: - Constants

    private enum Constants {
        static let tableSize: UInt32 = 256
        /// Minimum visible brightness (software brightness floor)
        static let minimumBrightness: Float = 0.08
        /// SDR brightness range (1.0 - minimumBrightness)
        static let sdrRange: Float = 0.92
        /// A freshly captured baseline whose values exceed this is already
        /// boosted (leftover from a crash or another app) — never scale on
        /// top of it.
        static let boostedBaselineThreshold: Float = 1.1
        /// Read-back comparison tolerance for drift detection. The OS may
        /// quantize written values slightly.
        static let driftTolerance: Float = 0.003
        /// Consecutive drift-reapply fights before declaring a conflict.
        static let maxConsecutiveDriftReapplies = 3
        /// Convergence threshold below which a fade applies directly.
        static let fadeEpsilon: Float = 0.001
    }

    // Default gamma table, captured on `readDefaultGamma` then read-only.
    @ObservationIgnored private var defaultGammaRed = [Float](repeating: 0, count: 256)
    @ObservationIgnored private var defaultGammaGreen = [Float](repeating: 0, count: 256)
    @ObservationIgnored private var defaultGammaBlue = [Float](repeating: 0, count: 256)
    @ObservationIgnored private var defaultGammaCount: UInt32 = 0

    // Reusable buffers for writeScaledTable to avoid per-call allocations.
    @ObservationIgnored private var scaledRed = [Float](repeating: 0, count: 256)
    @ObservationIgnored private var scaledGreen = [Float](repeating: 0, count: 256)
    @ObservationIgnored private var scaledBlue = [Float](repeating: 0, count: 256)

    private(set) var maxEDR: Float = 1.425738
    /// Raw display peak nits (from potential EDR) for OSD display.
    /// Distinct from `maxEDR` which is a gamma scaling ceiling.
    private(set) var displayPeakNits: Float = BrightnessNitsConverter.sdrMaxNits

    var onPersistentGammaConflict: (@MainActor () -> Void)?

    /// Software-brightness scale most recently written to the display.
    /// Fades start from here.
    private(set) var appliedSoftwareBrightness: Float = 1.0

    private let io: GammaTableIO
    private let fadeFrameInterval: Duration
    private let integrityPollInterval: Duration

    @ObservationIgnored private var fadeTask: Task<Void, Never>?
    @ObservationIgnored private var integrityTask: Task<Void, Never>?
    private var consecutiveDriftReapplies = 0
    /// Last values we wrote at the top of the table, for drift comparison.
    private var expectedTopValues: (red: Float, green: Float, blue: Float)?
    private var hasLoggedScaling = false

    init(io: GammaTableIO? = nil,
         fadeFrameInterval: Duration = .milliseconds(16),
         integrityPollInterval: Duration = .seconds(2)) {
        self.io = io ?? .live
        self.fadeFrameInterval = fadeFrameInterval
        self.integrityPollInterval = integrityPollInterval
    }

    // MARK: - Read Default Gamma

    func readDefaultGamma(displayID: UInt32) {
        guard var table = readValidTable(displayID: displayID) else {
            logger.error("Gamma table read failed or empty, using linear identity fallback")
            setLinearIdentityGamma()
            return
        }

        // Boosted-baseline guard: if the captured table is already scaled
        // above 1.0 (crash leftovers, another app), scaling on top of it
        // would double-boost. Restore ColorSync and re-read; if the OS
        // restore didn't help, normalize what we have.
        let capturedMax = maxValue(of: table)
        if capturedMax > Constants.boostedBaselineThreshold {
            logger.warning("Captured gamma baseline looks boosted (max \(capturedMax, privacy: .public)) — restoring ColorSync and re-reading")
            io.restoreColorSync()
            if let clean = readValidTable(displayID: displayID) {
                table = clean
            }
            let residualMax = maxValue(of: table)
            if residualMax > Constants.boostedBaselineThreshold {
                logger.warning("Baseline still boosted after restore (max \(residualMax, privacy: .public)) — normalizing captured table")
                var inverse = 1.0 / residualMax
                vDSP_vsmul(table.red, 1, &inverse, &table.red, 1, vDSP_Length(table.red.count))
                vDSP_vsmul(table.green, 1, &inverse, &table.green, 1, vDSP_Length(table.green.count))
                vDSP_vsmul(table.blue, 1, &inverse, &table.blue, 1, vDSP_Length(table.blue.count))
            }
        }

        defaultGammaRed = table.red
        defaultGammaGreen = table.green
        defaultGammaBlue = table.blue
        defaultGammaCount = table.count

        logger.info("Read gamma table: count=\(table.count, privacy: .public), R[0]=\(self.defaultGammaRed[0], privacy: .public), R[127]=\(self.defaultGammaRed[127], privacy: .public), R[255]=\(self.defaultGammaRed[255], privacy: .public), G[255]=\(self.defaultGammaGreen[255], privacy: .public), B[255]=\(self.defaultGammaBlue[255], privacy: .public)")
    }

    private func readValidTable(displayID: UInt32)
        -> (red: [Float], green: [Float], blue: [Float], count: UInt32)? {
        let result = io.readTable(displayID, Constants.tableSize)
        guard result.error == .success else { return nil }
        let count = result.sampleCount > 0 ? result.sampleCount : Constants.tableSize

        let sum = result.red.reduce(0, +) + result.green.reduce(0, +) + result.blue.reduce(0, +)
        guard sum > 0 else { return nil }

        return (result.red, result.green, result.blue, count)
    }

    private func maxValue(of table: (red: [Float], green: [Float], blue: [Float], count: UInt32)) -> Float {
        max(table.red.max() ?? 0, table.green.max() ?? 0, table.blue.max() ?? 0)
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

    // MARK: - EDR Headroom

    func updateEDRHeadroom(current: Double, potential: Double) {
        maxEDR = Self.computeMaxEDR(edr: current)
        displayPeakNits = max(BrightnessNitsConverter.sdrMaxNits, Float(potential) * 100.0)
    }

    // MARK: - Apply Scaled Gamma

    func applyScaledGamma(displayID: UInt32, softwareBrightness: Float? = nil) {
        fadeTask?.cancel()
        fadeTask = nil
        writeScaledTable(displayID: displayID, softwareBrightness: softwareBrightness ?? maxEDR)
        consecutiveDriftReapplies = 0
    }

    // MARK: - Fades

    func fadeToSoftwareBrightness(_ target: Float, displayID: UInt32, duration: TimeInterval) {
        fadeTask?.cancel()
        fadeTask = nil

        let start = appliedSoftwareBrightness
        guard duration > 0, abs(target - start) > Constants.fadeEpsilon else {
            writeScaledTable(displayID: displayID, softwareBrightness: target)
            consecutiveDriftReapplies = 0
            return
        }

        consecutiveDriftReapplies = 0
        fadeTask = Task { @MainActor [weak self] in
            let clock = ContinuousClock()
            let startInstant = clock.now
            while !Task.isCancelled {
                guard let self else { return }
                let elapsed = startInstant.duration(to: clock.now)
                let progress = min(1.0, Self.seconds(of: elapsed) / duration)
                let eased = progress * progress * (3.0 - 2.0 * progress)
                let value = start + (target - start) * Float(eased)
                self.writeScaledTable(displayID: displayID, softwareBrightness: value)
                if progress >= 1.0 { break }
                try? await Task.sleep(for: self.fadeFrameInterval)
            }
            guard !Task.isCancelled, let self else { return }
            if abs(self.appliedSoftwareBrightness - target) > Constants.fadeEpsilon {
                self.writeScaledTable(displayID: displayID, softwareBrightness: target)
            }
            self.fadeTask = nil
        }
    }

    private static func seconds(of duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) * 1e-18
    }

    // MARK: - Integrity Monitoring

    func startIntegrityMonitoring(displayID: UInt32) {
        guard integrityTask == nil else { return }
        integrityTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.integrityPollInterval else { return }
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self else { return }
                self.integrityTick(displayID: displayID)
            }
        }
    }

    private func integrityTick(displayID: UInt32) {
        // Skip while a fade is writing — intermediate values would look
        // like drift.
        guard fadeTask == nil, let expected = expectedTopValues else { return }

        let result = io.readTable(displayID, Constants.tableSize)
        guard result.error == .success, result.sampleCount > 0 else { return }
        let index = min(Int(result.sampleCount), Int(defaultGammaCount), result.red.count) - 1
        guard index >= 0 else { return }

        let drifted = abs(result.red[index] - expected.red) > Constants.driftTolerance
            || abs(result.green[index] - expected.green) > Constants.driftTolerance
            || abs(result.blue[index] - expected.blue) > Constants.driftTolerance

        guard drifted else {
            consecutiveDriftReapplies = 0
            return
        }

        consecutiveDriftReapplies += 1
        logger.warning("Gamma table drift detected (strike \(self.consecutiveDriftReapplies, privacy: .public)/\(Constants.maxConsecutiveDriftReapplies, privacy: .public)) — reapplying scale \(self.appliedSoftwareBrightness, privacy: .public)")
        writeScaledTable(displayID: displayID, softwareBrightness: appliedSoftwareBrightness)

        if consecutiveDriftReapplies >= Constants.maxConsecutiveDriftReapplies {
            logger.error("Persistent gamma conflict: our writes are not sticking (another gamma app, or CGSetDisplayTransferByTable is silently broken on this OS). Escalating.")
            consecutiveDriftReapplies = 0
            stopGammaActivity()
            onPersistentGammaConflict?()
        }
    }

    func stopGammaActivity() {
        fadeTask?.cancel()
        fadeTask = nil
        integrityTask?.cancel()
        integrityTask = nil
        consecutiveDriftReapplies = 0
    }

    func resetLogging() {
        hasLoggedScaling = false
    }

    // MARK: - Table Write

    private func writeScaledTable(displayID: UInt32, softwareBrightness sb: Float) {
        let count = Int(defaultGammaCount)
        guard count > 0 else { return }

        let brightness = (sb * 100.0).rounded() / 100.0
        let ceiling: Float = brightness > 1.0 ? maxEDR : 1.0
        let t = brightness / ceiling
        let scalingFactor = (ceiling - Constants.minimumBrightness) * t + Constants.minimumBrightness

        if !hasLoggedScaling {
            logger.info("Scaling: maxEDR=\(self.maxEDR, privacy: .public), brightness=\(brightness, privacy: .public), ceiling=\(ceiling, privacy: .public), t=\(t, privacy: .public), scalingFactor=\(scalingFactor, privacy: .public)")
            hasLoggedScaling = true
        }

        if scaledRed.count != count {
            scaledRed = [Float](repeating: 0, count: count)
            scaledGreen = [Float](repeating: 0, count: count)
            scaledBlue = [Float](repeating: 0, count: count)
        }

        var scale = scalingFactor
        vDSP_vsmul(defaultGammaRed, 1, &scale, &scaledRed, 1, vDSP_Length(count))
        vDSP_vsmul(defaultGammaGreen, 1, &scale, &scaledGreen, 1, vDSP_Length(count))
        vDSP_vsmul(defaultGammaBlue, 1, &scale, &scaledBlue, 1, vDSP_Length(count))

        let error = io.writeTable(displayID, scaledRed, scaledGreen, scaledBlue)
        if error != .success {
            logger.error("CGSetDisplayTransferByTable failed: \(error.rawValue, privacy: .public)")
        }

        appliedSoftwareBrightness = sb
        expectedTopValues = (scaledRed[count - 1], scaledGreen[count - 1], scaledBlue[count - 1])
    }

    // MARK: - Max EDR Polynomial

    /// Max EDR polynomial for mapping EDR headroom to brightness ceiling
    private static func computeMaxEDR(edr: Double) -> Float {
        let rawMax = edr * 0.227317 + 0.899816 + edr * edr * (-0.00590745)
        let capped = max(1.5667381, rawMax)
        return Float(capped + (-0.141))
    }
}
