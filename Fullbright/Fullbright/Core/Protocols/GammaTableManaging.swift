//
//  GammaTableManaging.swift
//  Fullbright
//
//  Gamma table management protocol.
//

import Foundation

@MainActor
protocol GammaTableManaging {
    var maxEDR: Float { get }

    func readDefaultGamma(displayID: UInt32)
    func recomputeMaxEDR()
    func softwareBrightness(from brightness: Float) -> Float
    func applyScaledGamma(displayID: UInt32, softwareBrightness: Float?)
    func startSmoothTransition(to target: Float, displayID: UInt32)
    func updateBrightness(from unifiedBrightness: Float)
    func stopTimer()
    func resetLogging()
}
