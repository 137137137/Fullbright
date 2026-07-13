//
//  CoreTestDoubles.swift
//  FullbrightTests
//
//  Doubles for the Core subsystem protocols so XDR orchestration and
//  controllers can be tested without touching DisplayServices, SkyLight,
//  CoreBrightness, or real gamma tables.
//

import Foundation
@testable import Fullbright

/// Shared append-only event log so tests can assert cross-stub ordering
/// (e.g. "compensation gamma was applied BEFORE the backlight was maxed").
@MainActor
final class RecordedEvents {
    private(set) var events: [String] = []

    func record(_ event: String) {
        events.append(event)
    }

    /// Index of the first event with the given prefix, or nil.
    func firstIndex(withPrefix prefix: String) -> Int? {
        events.firstIndex { $0.hasPrefix(prefix) }
    }
}

@MainActor
final class StubDisplayServices: DisplayServicesProviding {
    var storedBrightness: Float = 0.5
    /// nil simulates the private linear-brightness symbol being unavailable.
    var storedLinearBrightness: Float?
    var linearBrightnessCallCount = 0
    var lastLinearBrightness: Float = 0
    var ambientLightCompensationEnabled: Bool = true
    var setBrightnessCallCount = 0
    var getBrightnessCallCount = 0
    var eventLog: RecordedEvents?

    func getBrightness(_ displayID: UInt32) -> Float {
        getBrightnessCallCount += 1
        return storedBrightness
    }

    func getLinearBrightness(_ displayID: UInt32) -> Float? {
        storedLinearBrightness
    }

    @discardableResult
    func setBrightness(_ displayID: UInt32, _ value: Float) -> Bool {
        setBrightnessCallCount += 1
        storedBrightness = value
        eventLog?.record("setBrightness(\(value))")
        return true
    }

    @discardableResult
    func setLinearBrightness(_ displayID: UInt32, _ value: Float) -> Bool {
        linearBrightnessCallCount += 1
        lastLinearBrightness = value
        eventLog?.record("setLinearBrightness(\(value))")
        return true
    }

    @discardableResult
    func setAmbientLightCompensation(_ displayID: UInt32, enabled: Bool) -> Bool {
        ambientLightCompensationEnabled = enabled
        return true
    }
}

@MainActor
final class StubNightShiftManager: NightShiftManaging {
    var isEnabled: Bool
    var setEnabledCalls: [Bool] = []

    init(startEnabled: Bool = false) {
        self.isEnabled = startEnabled
    }

    func setEnabled(_ enabled: Bool) {
        setEnabledCalls.append(enabled)
        isEnabled = enabled
    }
}

@MainActor
final class StubDisplayConfigurator: DisplayConfiguring {
    var configureForXDRCalls: [UInt32] = []

    func configureForXDR(displayID: UInt32) {
        configureForXDRCalls.append(displayID)
    }
}

@MainActor
final class StubXDRDirtyFlagStore: XDRDirtyFlagStoring {
    var isDirty: Bool = false
    private(set) var restoreIfNeededCallCount = 0

    func restoreIfNeeded() {
        restoreIfNeededCallCount += 1
        if isDirty { isDirty = false }
    }
}

@MainActor
final class StubGammaTableManager: GammaTableManaging {
    var maxEDR: Float = 1.6
    var displayPeakNits: Float = 1600
    var onPersistentGammaConflict: (@MainActor () -> Void)?

    var readDefaultGammaCount = 0
    var updateEDRHeadroomCalls: [(current: Double, potential: Double)] = []
    var applyScaledGammaCalls: [(displayID: UInt32, softwareBrightness: Float?)] = []
    var fadeCalls: [(target: Float, displayID: UInt32, duration: TimeInterval)] = []
    var startIntegrityMonitoringCount = 0
    var stopGammaActivityCount = 0
    var resetLoggingCount = 0
    var eventLog: RecordedEvents?

    func readDefaultGamma(displayID: UInt32) {
        readDefaultGammaCount += 1
        eventLog?.record("readDefaultGamma")
    }

    func updateEDRHeadroom(current: Double, potential: Double) {
        updateEDRHeadroomCalls.append((current, potential))
    }

    /// Doubled passthrough so unified 1.0 maps above the SDR clamp (2.0),
    /// letting tests distinguish clamped (≤1.0) from unclamped targets.
    func softwareBrightness(from brightness: Float) -> Float {
        brightness * 2.0
    }

    func applyScaledGamma(displayID: UInt32, softwareBrightness: Float?) {
        applyScaledGammaCalls.append((displayID, softwareBrightness))
        eventLog?.record("applyScaledGamma(\(softwareBrightness.map(String.init) ?? "nil"))")
    }

    func fadeToSoftwareBrightness(_ target: Float, displayID: UInt32, duration: TimeInterval) {
        fadeCalls.append((target, displayID, duration))
        eventLog?.record("fade(\(target))")
    }

    func startIntegrityMonitoring(displayID: UInt32) {
        startIntegrityMonitoringCount += 1
    }

    func stopGammaActivity() {
        stopGammaActivityCount += 1
    }

    func resetLogging() {
        resetLoggingCount += 1
    }
}

@MainActor
final class StubEDRSignal: EDRSignalProviding {
    var currentHeadroomValue: Double = 1.0
    var potentialHeadroomValue: Double = 16.0

    func currentHeadroom(displayID: UInt32) -> Double {
        currentHeadroomValue
    }

    func potentialHeadroom(displayID: UInt32) -> Double {
        potentialHeadroomValue
    }
}

@MainActor
final class StubDisplayLifecycleObserver: DisplayLifecycleObserving {
    var onScreensSleep: (@MainActor () -> Void)?
    var onWake: (@MainActor () -> Void)?
    var onDisplayParametersChanged: (@MainActor () -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() { startCount += 1 }
    func stop() { stopCount += 1 }

    // Test helpers to simulate system events.
    func fireScreensSleep() { onScreensSleep?() }
    func fireWake() { onWake?() }
    func fireDisplayParametersChanged() { onDisplayParametersChanged?() }
}
