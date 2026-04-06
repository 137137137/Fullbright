//
//  NightShiftManager.swift
//  Fullbright
//
//  Night Shift state via private CBBlueLightClient API.
//

import Foundation
import AppKit

@MainActor
final class NightShiftManager: NightShiftManaging {
    private let blueLightClient: NSObject?

    private static let coreBrightnessPath = "/System/Library/PrivateFrameworks/CoreBrightness.framework/Versions/A/CoreBrightness"

    init() {
        _ = PrivateFrameworkLoader.loadFramework(Self.coreBrightnessPath)
        blueLightClient = Self.createBlueLightClient()
    }

    var isEnabled: Bool {
        guard let client = blueLightClient else { return false }
        let sel = NSSelectorFromString("getBlueLightStatus:")
        guard client.responds(to: sel) else { return false }
        var status = [UInt8](repeating: 0, count: 512)
        typealias Fn = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Bool
        _ = unsafeBitCast(client.method(for: sel), to: Fn.self)(client, sel, &status)
        // Ghidra: byte at offset 1 is the enabled field
        return status[1] != 0
    }

    func setEnabled(_ enabled: Bool) {
        guard let client = blueLightClient else { return }
        let sel = NSSelectorFromString("setEnabled:")
        guard client.responds(to: sel) else { return }
        typealias Fn = @convention(c) (AnyObject, Selector, Bool) -> Void
        unsafeBitCast(client.method(for: sel), to: Fn.self)(client, sel, enabled)
    }

    private static func createBlueLightClient() -> NSObject? {
        guard let cls = NSClassFromString("CBBlueLightClient") as? NSObject.Type else { return nil }
        return cls.init()
    }
}
