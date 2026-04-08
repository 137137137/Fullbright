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

@MainActor
final class StubDisplayServices: DisplayServicesProviding {
    var storedBrightness: Float = 0.5
    var linearBrightnessCallCount = 0
    var lastLinearBrightness: Float = 0
    var ambientLightCompensationEnabled: Bool = true
    var setBrightnessCallCount = 0
    var getBrightnessCallCount = 0

    func getBrightness(_ displayID: UInt32) -> Float {
        getBrightnessCallCount += 1
        return storedBrightness
    }

    @discardableResult
    func setBrightness(_ displayID: UInt32, _ value: Float) -> Bool {
        setBrightnessCallCount += 1
        storedBrightness = value
        return true
    }

    @discardableResult
    func setLinearBrightness(_ displayID: UInt32, _ value: Float) -> Bool {
        linearBrightnessCallCount += 1
        lastLinearBrightness = value
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

    var readDefaultGammaCount = 0
    var recomputeMaxEDRCount = 0
    var stopRenderLoopCount = 0
    var resetLoggingCount = 0
    var applyScaledGammaCalls: [(UInt32, Float?)] = []
    var startSmoothTransitionCalls: [(Float, UInt32)] = []
    var updateBrightnessCalls: [Float] = []

    func readDefaultGamma(displayID: UInt32) {
        readDefaultGammaCount += 1
    }

    func recomputeMaxEDR() {
        recomputeMaxEDRCount += 1
    }

    func softwareBrightness(from brightness: Float) -> Float {
        // Linear passthrough is enough for orchestration tests.
        brightness
    }

    func applyScaledGamma(displayID: UInt32, softwareBrightness: Float?) {
        applyScaledGammaCalls.append((displayID, softwareBrightness))
    }

    func startSmoothTransition(to target: Float, displayID: UInt32) {
        startSmoothTransitionCalls.append((target, displayID))
    }

    func updateBrightness(from unifiedBrightness: Float) {
        updateBrightnessCalls.append(unifiedBrightness)
    }

    func stopRenderLoop() {
        stopRenderLoopCount += 1
    }

    func resetLogging() {
        resetLoggingCount += 1
    }
}
