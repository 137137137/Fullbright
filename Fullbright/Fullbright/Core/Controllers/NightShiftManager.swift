//
//  NightShiftManager.swift
//  Fullbright
//
//  Night Shift state via private CBBlueLightClient API.
//
//  Previous implementation used `unsafeBitCast(client.method(for: sel), to: Fn.self)`
//  — casting an Objective-C IMP to a typed C function pointer. That's
//  undefined behavior under Apple's ABI guarantees: the calling convention
//  of a Swift `@convention(c)` pointer is not the same as `objc_msgSend`,
//  which takes `(id, SEL, ...)`. On arm64/x86_64 they happen to work, but
//  the compiler is allowed to break it.
//
//  The current implementation declares an `@objc protocol CBBlueLightClientShim`
//  describing the subset of CBBlueLightClient methods we call. The instance
//  is bridged to the shim via `unsafeBitCast(instance, to: (any Shim).self)`
//  — a pointer-identity cast, NOT a method-table cast — and all calls go
//  through the normal `objc_msgSend` dispatch path that Swift emits for
//  `@objc` protocol methods. That's the correct, ABI-stable way to call
//  into a dynamically-loaded ObjC class whose @interface we can't import.
//

import Foundation
import AppKit

/// Subset of Apple's private `CBBlueLightClient` Objective-C interface that
/// we depend on. The real class lives in CoreBrightness.framework and isn't
/// exposed in any public header, so we describe it here and cast to it.
///
/// Selector names must match CBBlueLightClient exactly. Breakage on a future
/// macOS version is detected via `responds(to:)` guards at each call site.
@objc private protocol CBBlueLightClientShim: NSObjectProtocol {
    func getBlueLightStatus(_ status: UnsafeMutableRawPointer) -> Bool
    func setEnabled(_ enabled: ObjCBool)
}

/// Byte-offset constants for the `CBBlueLightStatus` C struct that
/// `getBlueLightStatus:` writes into. Reverse-engineered from the published
/// CBBlueLightClient headers used by projects like Lunar and f.lux; verified
/// stable from macOS 10.12 through 26 as of 2026-04. Only the first three
/// boolean fields are guaranteed stable — later fields drift across versions,
/// so we intentionally don't read them.
private enum CBBlueLightStatusLayout {
    /// Whether Night Shift is currently *running* (schedule has triggered).
    static let activeOffset = 0
    /// Whether Night Shift is *enabled* by the user (master toggle).
    static let enabledOffset = 1
    /// Whether the system permits sunrise/sunset scheduling.
    static let sunSchedulePermittedOffset = 2
    /// Buffer size we allocate for the status struct. The real struct is
    /// smaller than this on all known OS versions; we over-allocate so
    /// future field additions can't cause a stack overflow.
    static let bufferSize = 128
}

@MainActor
final class NightShiftManager: NightShiftManaging {
    private let blueLightClient: (any CBBlueLightClientShim)?

    private static let coreBrightnessPath = "/System/Library/PrivateFrameworks/CoreBrightness.framework/Versions/A/CoreBrightness"

    init() {
        _ = PrivateFrameworkLoader.loadFramework(Self.coreBrightnessPath)
        blueLightClient = Self.createBlueLightClient()
    }

    var isEnabled: Bool {
        guard let client = blueLightClient else { return false }

        // Defensive: if a future macOS version renames the selector, fail
        // closed rather than crash on a missing method.
        let selector = NSSelectorFromString("getBlueLightStatus:")
        guard client.responds(to: selector) else { return false }

        var buffer = [UInt8](repeating: 0, count: CBBlueLightStatusLayout.bufferSize)
        let ok = buffer.withUnsafeMutableBytes { ptr -> Bool in
            guard let base = ptr.baseAddress else { return false }
            return client.getBlueLightStatus(base)
        }
        guard ok else { return false }
        return buffer[CBBlueLightStatusLayout.enabledOffset] != 0
    }

    func setEnabled(_ enabled: Bool) {
        guard let client = blueLightClient else { return }
        let selector = NSSelectorFromString("setEnabled:")
        guard client.responds(to: selector) else { return }
        client.setEnabled(ObjCBool(enabled))
    }

    private static func createBlueLightClient() -> (any CBBlueLightClientShim)? {
        guard let cls = NSClassFromString("CBBlueLightClient") as? NSObject.Type else { return nil }
        let instance = cls.init()
        // Pointer-identity bridge: @objc protocols are represented as `id<P>`
        // which is a raw object pointer at runtime, so this cast is free and
        // does not mutate the vtable. All subsequent method calls dispatch
        // through objc_msgSend via the selector — the correct ABI.
        return unsafeBitCast(instance, to: (any CBBlueLightClientShim).self)
    }
}
