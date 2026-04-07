//
//  DisplayServicesProviding.swift
//  Fullbright
//
//  Display brightness services protocol.
//

import Foundation

/// DisplayServices private-framework operations. Setters return `true` on
/// success. `@discardableResult` is intentionally NOT used — callers are
/// required to either `_ = ...` the result or log failures — so silent
/// swallowing of private-API failures becomes a compile error instead of a
/// runtime mystery.
@MainActor
protocol DisplayServicesProviding {
    func getBrightness(_ displayID: UInt32) -> Float
    func setBrightness(_ displayID: UInt32, _ value: Float) -> Bool
    func setLinearBrightness(_ displayID: UInt32, _ value: Float) -> Bool
    func setAmbientLightCompensation(_ displayID: UInt32, enabled: Bool) -> Bool
}
