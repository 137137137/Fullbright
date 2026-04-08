//
//  BrightnessNitsConverterTests.swift
//  FullbrightTests
//

import Testing
@testable import Fullbright

struct BrightnessNitsConverterTests {

    @Test func sdrFloorIsClampedToOne() {
        #expect(BrightnessNitsConverter.nits(from: 0.0, maxNits: 1600) == 1)
    }

    @Test func sdrMidpointIsHalfOfSdrMax() {
        #expect(BrightnessNitsConverter.nits(from: 0.25, maxNits: 1600) == 250)
    }

    @Test func sdrXdrBoundaryIsExactlySdrMax() {
        #expect(BrightnessNitsConverter.nits(from: 0.5, maxNits: 1600) == 500)
    }

    @Test func xdrMaxReachesDisplayPeak() {
        #expect(BrightnessNitsConverter.nits(from: 1.0, maxNits: 1600) == 1600)
    }

    @Test func xdrMidpointIsHalfwayBetweenSdrMaxAndPeak() {
        // 0.75 -> halfway through XDR range: 500 + 0.5*(1600-500) = 1050
        #expect(BrightnessNitsConverter.nits(from: 0.75, maxNits: 1600) == 1050)
    }

    @Test func xdrIsMonotonicallyIncreasing() {
        let samples: [Float] = [0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
        let values = samples.map { BrightnessNitsConverter.nits(from: $0, maxNits: 1600) }
        for i in 1..<values.count {
            #expect(values[i] >= values[i - 1])
        }
    }

    @Test func lowPeakClampsXdrRangeWithoutGoingNegative() {
        // Guard against the regression where small maxNits made the XDR range
        // negative and the displayed nits counted DOWN past the SDR boundary.
        let value = BrightnessNitsConverter.nits(from: 1.0, maxNits: 300)
        #expect(value >= 500)
    }

    @Test func boundaryConstantMatchesSdrXdrSplit() {
        #expect(BrightnessNitsConverter.sdrXDRBoundary == 0.5)
        #expect(BrightnessNitsConverter.sdrMaxNits == 500.0)
    }

    @Test func sdrIsMonotonicallyIncreasing() {
        let samples: [Float] = [0.0, 0.1, 0.2, 0.3, 0.4, 0.5]
        let values = samples.map { BrightnessNitsConverter.nits(from: $0, maxNits: 1600) }
        for i in 1..<values.count {
            #expect(values[i] >= values[i - 1])
        }
    }
}
