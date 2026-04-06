//
//  BrightnessNitsConverter.swift
//  Fullbright
//
//  Brightness <-> nits conversion.
//

import Foundation

enum BrightnessNitsConverter {
    /// Maximum nits for standard dynamic range
    static let sdrMaxNits: Float = 500.0
    /// Unified brightness value at the SDR/XDR boundary
    static let sdrXDRBoundary: Float = 0.5

    /// Convert unified brightness (0.0-1.0) to nits display value.
    /// SDR range (0.0-0.5): ~1 nit to ~500 nits.
    /// XDR range (0.5-1.0): ~500 nits to maxEDR*100 nits.
    static func nits(from brightness: Float, maxEDR: Float) -> Int {
        if brightness <= sdrXDRBoundary {
            return max(1, Int(brightness * 2.0 * sdrMaxNits))
        } else {
            let maxXDRNits = maxEDR * 100.0
            let xdrRange = maxXDRNits - sdrMaxNits
            return Int(sdrMaxNits + (brightness - sdrXDRBoundary) * 2.0 * xdrRange)
        }
    }
}
