//
//  GammaTableManagerTests.swift
//  FullbrightTests
//

import Testing
@testable import Fullbright

@MainActor
struct GammaTableManagerTests {

    @Test func softwareBrightness_atZero_isMinimumFloor() {
        let manager = GammaTableManager()
        let result = manager.softwareBrightness(from: 0.0)
        #expect(abs(result - 0.08) < 0.0001)
    }

    @Test func softwareBrightness_atSdrBoundary_isUnity() {
        let manager = GammaTableManager()
        let result = manager.softwareBrightness(from: 0.5)
        #expect(abs(result - 1.0) < 0.0001)
    }

    @Test func softwareBrightness_atOne_isMaxEDR() {
        let manager = GammaTableManager()
        let result = manager.softwareBrightness(from: 1.0)
        #expect(abs(result - manager.maxEDR) < 0.0001)
    }

    @Test func softwareBrightness_isMonotonicAcrossSdrAndXdr() {
        let manager = GammaTableManager()
        let samples: [Float] = [0.0, 0.1, 0.25, 0.4, 0.5, 0.6, 0.75, 0.9, 1.0]
        let values = samples.map { manager.softwareBrightness(from: $0) }
        for i in 1..<values.count {
            #expect(values[i] >= values[i - 1])
        }
    }

    @Test func softwareBrightness_quarterPoint_isMidwayBetweenFloorAndUnity() {
        let manager = GammaTableManager()
        // brightness 0.25 → t=0.5 → 0.08 + 0.5 * 0.92 = 0.54
        let result = manager.softwareBrightness(from: 0.25)
        #expect(abs(result - 0.54) < 0.0001)
    }
}
