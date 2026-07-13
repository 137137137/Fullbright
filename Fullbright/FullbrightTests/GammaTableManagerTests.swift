//
//  GammaTableManagerTests.swift
//  FullbrightTests
//

import Foundation
import CoreGraphics
import Testing
@testable import Fullbright

/// In-memory stand-in for the display's gamma table so fades, drift
/// detection, and baseline capture can be tested deterministically.
@MainActor
final class FakeGammaTableStore {
    /// The "hardware" table. Starts as a linear identity ramp.
    var red: [Float]
    var green: [Float]
    var blue: [Float]
    var sampleCount: UInt32 = 256
    var readError: CGError = .success
    var writeError: CGError = .success

    /// When true, writes are accepted (recorded) but the stored table is
    /// left untouched — simulating the macOS-beta bug where
    /// CGSetDisplayTransferByTable returns success and does nothing, or an
    /// external app immediately clobbering our writes.
    var writesSilentlyIgnored = false

    private(set) var writeCount = 0
    private(set) var restoreCount = 0
    /// Top-of-table red value after each write, for fade-shape assertions.
    private(set) var writtenTopValues: [Float] = []

    init(scale: Float = 1.0) {
        let ramp = (0..<256).map { Float($0) / 255.0 * scale }
        red = ramp
        green = ramp
        blue = ramp
    }

    var io: GammaTableIO {
        GammaTableIO(
            readTable: { [weak self] _, capacity in
                guard let self else {
                    return ([], [], [], 0, CGError.failure)
                }
                guard self.readError == .success else {
                    return ([Float](repeating: 0, count: Int(capacity)),
                            [Float](repeating: 0, count: Int(capacity)),
                            [Float](repeating: 0, count: Int(capacity)),
                            0, self.readError)
                }
                return (self.red, self.green, self.blue, self.sampleCount, .success)
            },
            writeTable: { [weak self] _, red, green, blue in
                guard let self else { return CGError.failure }
                self.writeCount += 1
                self.writtenTopValues.append(red.last ?? 0)
                if !self.writesSilentlyIgnored && self.writeError == .success {
                    self.red = red
                    self.green = green
                    self.blue = blue
                }
                return self.writeError
            },
            restoreColorSync: { [weak self] in
                guard let self else { return }
                self.restoreCount += 1
                // The OS restore resets the table to the identity ramp.
                let ramp = (0..<256).map { Float($0) / 255.0 }
                self.red = ramp
                self.green = ramp
                self.blue = ramp
            }
        )
    }
}

@MainActor
struct GammaTableManagerTests {

    private func makeManager(
        store: FakeGammaTableStore = FakeGammaTableStore(),
        integrityPollInterval: Duration = .milliseconds(10)
    ) -> (GammaTableManager, FakeGammaTableStore) {
        let manager = GammaTableManager(
            io: store.io,
            fadeFrameInterval: .milliseconds(2),
            integrityPollInterval: integrityPollInterval
        )
        return (manager, store)
    }

    @discardableResult
    private func waitUntil(
        timeoutMs: Int = 2000,
        _ condition: @MainActor () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + .milliseconds(timeoutMs)
        while clock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    // MARK: - Software brightness mapping

    @Test func softwareBrightness_atZero_isMinimumFloor() {
        let (manager, _) = makeManager()
        let result = manager.softwareBrightness(from: 0.0)
        #expect(abs(result - 0.08) < 0.0001)
    }

    @Test func softwareBrightness_atSdrBoundary_isUnity() {
        let (manager, _) = makeManager()
        let result = manager.softwareBrightness(from: 0.5)
        #expect(abs(result - 1.0) < 0.0001)
    }

    @Test func softwareBrightness_atOne_isMaxEDR() {
        let (manager, _) = makeManager()
        let result = manager.softwareBrightness(from: 1.0)
        #expect(abs(result - manager.maxEDR) < 0.0001)
    }

    @Test func softwareBrightness_isMonotonicAcrossSdrAndXdr() {
        let (manager, _) = makeManager()
        let samples: [Float] = [0.0, 0.1, 0.25, 0.4, 0.5, 0.6, 0.75, 0.9, 1.0]
        let values = samples.map { manager.softwareBrightness(from: $0) }
        for i in 1..<values.count {
            #expect(values[i] >= values[i - 1])
        }
    }

    @Test func softwareBrightness_quarterPoint_isMidwayBetweenFloorAndUnity() {
        let (manager, _) = makeManager()
        // brightness 0.25 → t=0.5 → 0.08 + 0.5 * 0.92 = 0.54
        let result = manager.softwareBrightness(from: 0.25)
        #expect(abs(result - 0.54) < 0.0001)
    }

    // MARK: - EDR headroom

    @Test func updateEDRHeadroom_setsCeilingAndPeakNits() {
        let (manager, _) = makeManager()
        manager.updateEDRHeadroom(current: 2.0, potential: 16.0)
        #expect(manager.maxEDR > 1.0)
        #expect(manager.displayPeakNits == 1600)
    }

    @Test func updateEDRHeadroom_peakNitsNeverBelowSDRMax() {
        let (manager, _) = makeManager()
        manager.updateEDRHeadroom(current: 1.0, potential: 1.0)
        #expect(manager.displayPeakNits == BrightnessNitsConverter.sdrMaxNits)
    }

    // MARK: - Baseline capture

    @Test func readDefaultGamma_capturesCleanBaseline() {
        let (manager, store) = makeManager()
        manager.readDefaultGamma(displayID: 1)
        #expect(store.restoreCount == 0)

        // Applying full SDR scale (1.0) rewrites the identity ramp.
        manager.applyScaledGamma(displayID: 1, softwareBrightness: 1.0)
        #expect(store.writeCount == 1)
        // Scaling factor at sb=1.0 is 1.0, so the top value stays ~1.0.
        #expect(abs((store.writtenTopValues.last ?? 0) - 1.0) < 0.001)
    }

    @Test func readDefaultGamma_boostedBaseline_restoresAndRereads() {
        // Hardware table is boosted 1.4x (crash leftovers).
        let store = FakeGammaTableStore(scale: 1.4)
        let (manager, _) = makeManager(store: store)

        manager.readDefaultGamma(displayID: 1)

        // The guard must restore ColorSync (fake resets to identity) and
        // capture the clean table.
        #expect(store.restoreCount == 1)
        manager.applyScaledGamma(displayID: 1, softwareBrightness: 1.0)
        #expect(abs((store.writtenTopValues.last ?? 0) - 1.0) < 0.001)
    }

    @Test func readDefaultGamma_stubbornBoostedBaseline_normalizes() async {
        let store = FakeGammaTableStore(scale: 1.4)

        // Make the restore ineffective: table stays boosted after restore.
        // Simplest hostile simulation: restore re-boosts the table.
        let hostileIO = GammaTableIO(
            readTable: store.io.readTable,
            writeTable: store.io.writeTable,
            restoreColorSync: { /* restore does nothing */ }
        )
        let stubborn = GammaTableManager(
            io: hostileIO,
            fadeFrameInterval: .milliseconds(2),
            integrityPollInterval: .milliseconds(10)
        )

        stubborn.readDefaultGamma(displayID: 1)
        stubborn.applyScaledGamma(displayID: 1, softwareBrightness: 1.0)

        // Normalized baseline: top value ≈ 1.0 even though hardware said 1.4.
        #expect(abs((store.writtenTopValues.last ?? 0) - 1.0) < 0.001)
    }

    // MARK: - Fades

    @Test func fade_zeroDuration_appliesImmediately() {
        let (manager, store) = makeManager()
        manager.readDefaultGamma(displayID: 1)
        manager.fadeToSoftwareBrightness(0.5, displayID: 1, duration: 0)
        #expect(store.writeCount == 1)
        #expect(abs(manager.appliedSoftwareBrightness - 0.5) < 0.0001)
    }

    @Test func fade_reachesTargetAndWritesIntermediateSteps() async {
        let (manager, store) = makeManager()
        manager.readDefaultGamma(displayID: 1)
        manager.applyScaledGamma(displayID: 1, softwareBrightness: 0.2)

        manager.fadeToSoftwareBrightness(1.0, displayID: 1, duration: 0.05)
        let converged = await waitUntil {
            abs(manager.appliedSoftwareBrightness - 1.0) < 0.0001
        }
        #expect(converged)
        // More than start+end writes → intermediate frames happened.
        #expect(store.writeCount > 2)
        // Monotonic non-decreasing progression for an upward fade.
        let tops = store.writtenTopValues
        for i in 1..<tops.count {
            #expect(tops[i] >= tops[i - 1] - 0.0001)
        }
    }

    @Test func fade_retarget_cancelsPreviousFade() async {
        let (manager, _) = makeManager()
        manager.readDefaultGamma(displayID: 1)
        manager.applyScaledGamma(displayID: 1, softwareBrightness: 0.2)

        manager.fadeToSoftwareBrightness(1.0, displayID: 1, duration: 10.0)
        try? await Task.sleep(for: .milliseconds(10))
        manager.fadeToSoftwareBrightness(0.3, displayID: 1, duration: 0.03)

        let converged = await waitUntil {
            abs(manager.appliedSoftwareBrightness - 0.3) < 0.0001
        }
        #expect(converged)
        // Stays at the retargeted value (first fade is dead).
        try? await Task.sleep(for: .milliseconds(50))
        #expect(abs(manager.appliedSoftwareBrightness - 0.3) < 0.0001)
    }

    // MARK: - Drift detection

    @Test func integrity_noDrift_doesNotRewrite() async {
        let (manager, store) = makeManager()
        manager.readDefaultGamma(displayID: 1)
        manager.applyScaledGamma(displayID: 1, softwareBrightness: 0.8)
        let writesAfterApply = store.writeCount

        manager.startIntegrityMonitoring(displayID: 1)
        try? await Task.sleep(for: .milliseconds(80))
        manager.stopGammaActivity()

        #expect(store.writeCount == writesAfterApply)
    }

    @Test func integrity_singleDrift_reappliesAndRecovers() async {
        let (manager, store) = makeManager()
        manager.readDefaultGamma(displayID: 1)
        manager.applyScaledGamma(displayID: 1, softwareBrightness: 0.8)

        var conflictFired = false
        manager.onPersistentGammaConflict = { conflictFired = true }
        manager.startIntegrityMonitoring(displayID: 1)

        // External writer clobbers the table once; our reapply then sticks.
        store.red = store.red.map { $0 * 0.5 }
        store.green = store.green.map { $0 * 0.5 }
        store.blue = store.blue.map { $0 * 0.5 }

        let writesBefore = store.writeCount
        let reapplied = await waitUntil { store.writeCount > writesBefore }
        #expect(reapplied)

        // Give it several more poll cycles: no conflict, no more rewrites.
        try? await Task.sleep(for: .milliseconds(100))
        manager.stopGammaActivity()
        #expect(conflictFired == false)
    }

    @Test func integrity_persistentDrift_escalatesToConflict() async {
        let (manager, store) = makeManager()
        manager.readDefaultGamma(displayID: 1)
        manager.applyScaledGamma(displayID: 1, softwareBrightness: 0.8)

        var conflictFired = false
        manager.onPersistentGammaConflict = { conflictFired = true }

        // From now on, writes are silently ignored (broken API / hostile app)
        // and the visible table is someone else's.
        store.writesSilentlyIgnored = true
        store.red = store.red.map { $0 * 0.5 }
        store.green = store.green.map { $0 * 0.5 }
        store.blue = store.blue.map { $0 * 0.5 }

        manager.startIntegrityMonitoring(displayID: 1)
        let escalated = await waitUntil { conflictFired }
        #expect(escalated)
    }

    @Test func stopGammaActivity_haltsIntegrityMonitoring() async {
        let (manager, store) = makeManager()
        manager.readDefaultGamma(displayID: 1)
        manager.applyScaledGamma(displayID: 1, softwareBrightness: 0.8)
        manager.startIntegrityMonitoring(displayID: 1)
        manager.stopGammaActivity()

        store.red = store.red.map { $0 * 0.5 }
        let writesBefore = store.writeCount
        try? await Task.sleep(for: .milliseconds(80))
        #expect(store.writeCount == writesBefore)
    }
}
