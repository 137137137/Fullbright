//
//  DisplayServicesProviding.swift
//  Fullbright
//
//  Display brightness services protocol.
//

import Foundation

@MainActor
protocol DisplayServicesProviding {
    func getBrightness(_ displayID: UInt32) -> Float
    @discardableResult func setBrightness(_ displayID: UInt32, _ value: Float) -> Bool
    @discardableResult func setLinearBrightness(_ displayID: UInt32, _ value: Float) -> Bool
    @discardableResult func setAmbientLightCompensation(_ displayID: UInt32, enabled: Bool) -> Bool
}
