//
//  DisplayServicesClient.swift
//  Fullbright
//
//  DisplayServices private framework function pointers.
//

import Foundation
import CoreGraphics

// Verified function signatures from Ghidra + LLDB:
private typealias DSGetBrightnessFunc = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
private typealias DSSetBrightnessFunc = @convention(c) (UInt32, Float) -> Int32
private typealias DSSetLinearBrightnessFunc = @convention(c) (UInt32, Float) -> Int32
// EnableALC takes TWO params: (displayID, enabled) — verified from Ghidra call sites
private typealias DSEnableALCFunc = @convention(c) (UInt32, Bool) -> Int32

private let displayServicesPath = "/System/Library/PrivateFrameworks/DisplayServices.framework/Versions/A/DisplayServices"

@MainActor
final class DisplayServicesClient: DisplayServicesProviding {
    private let fnGetBrightness: DSGetBrightnessFunc?
    private let fnSetBrightness: DSSetBrightnessFunc?
    private let fnSetLinearBrightness: DSSetLinearBrightnessFunc?
    private let fnEnableALC: DSEnableALCFunc?

    init() {
        if let handle = PrivateFrameworkLoader.loadFramework(displayServicesPath) {
            fnGetBrightness = PrivateFrameworkLoader.symbol("DisplayServicesGetBrightness", from: handle, as: DSGetBrightnessFunc.self)
            fnSetBrightness = PrivateFrameworkLoader.symbol("DisplayServicesSetBrightness", from: handle, as: DSSetBrightnessFunc.self)
            fnSetLinearBrightness = PrivateFrameworkLoader.symbol("DisplayServicesSetLinearBrightness", from: handle, as: DSSetLinearBrightnessFunc.self)
            fnEnableALC = PrivateFrameworkLoader.symbol("DisplayServicesEnableAmbientLightCompensation", from: handle, as: DSEnableALCFunc.self)
        } else {
            fnGetBrightness = nil
            fnSetBrightness = nil
            fnSetLinearBrightness = nil
            fnEnableALC = nil
        }
    }

    func getBrightness(_ displayID: UInt32) -> Float {
        guard let fn = fnGetBrightness else { return 0 }
        var b: Float = 0
        _ = fn(displayID, &b)
        return b
    }

    @discardableResult
    func setBrightness(_ displayID: UInt32, _ value: Float) -> Bool {
        guard let fn = fnSetBrightness else { return false }
        return fn(displayID, value) == 0
    }

    @discardableResult
    func setLinearBrightness(_ displayID: UInt32, _ value: Float) -> Bool {
        guard let fn = fnSetLinearBrightness else { return false }
        return fn(displayID, value) == 0
    }

    @discardableResult
    func setAmbientLightCompensation(_ displayID: UInt32, enabled: Bool) -> Bool {
        guard let fn = fnEnableALC else { return false }
        return fn(displayID, enabled) == 0
    }
}
