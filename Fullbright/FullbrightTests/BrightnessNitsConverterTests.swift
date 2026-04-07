//
//  BrightnessNitsConverterTests.swift
//  FullbrightTests
//

import Testing
@testable import Fullbright

struct BrightnessNitsConverterTests {

    @Test func sdrFloorIsClampedToOne() {
        #expect(BrightnessNitsConverter.nits(from: 0.0, maxEDR: 1.5) == 1)
    }

    @Test func sdrMidpointIsHalfOfSdrMax() {
        #expect(BrightnessNitsConverter.nits(from: 0.25, maxEDR: 1.5) == 250)
    }

    @Test func sdrXdrBoundaryIsExactlySdrMax() {
        #expect(BrightnessNitsConverter.nits(from: 0.5, maxEDR: 1.5) == 500)
    }

    @Test func boundaryConstantMatchesSdrXdrSplit() {
        #expect(BrightnessNitsConverter.sdrXDRBoundary == 0.5)
        #expect(BrightnessNitsConverter.sdrMaxNits == 500.0)
    }

    @Test func sdrIsMonotonicallyIncreasing() {
        let samples: [Float] = [0.0, 0.1, 0.2, 0.3, 0.4, 0.5]
        let values = samples.map { BrightnessNitsConverter.nits(from: $0, maxEDR: 1.5) }
        for i in 1..<values.count {
            #expect(values[i] >= values[i - 1])
        }
    }
}
