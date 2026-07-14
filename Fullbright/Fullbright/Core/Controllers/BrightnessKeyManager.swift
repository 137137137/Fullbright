//
//  BrightnessKeyManager.swift
//  Fullbright
//
//  Intercepts brightness media keys via CGEventTap.
//  Always suppresses the native macOS OSD and routes brightness
//  keys to XDR brightness control (600–1600 nits range).
//

import Foundation
import CoreGraphics
import AppKit
import os

private let logger = Logger(subsystem: AppIdentifier.serviceID, category: "BrightnessKeys")

@MainActor
final class BrightnessKeyManager: BrightnessKeyManaging {
    init() {}

    // MARK: - Constants

    private enum MediaKey {
        /// NX_SYSDEFINED event type
        static let sysDefinedEventType: UInt32 = 14
        /// Media key subtype
        static let mediaKeySubtype: Int16 = 8
        /// Bitmask to extract key code from NSEvent.data1 (upper 16 bits)
        static let keyCodeMask: Int = 0xFFFF0000
        /// Bitmask to extract key flags from NSEvent.data1 (lower 16 bits)
        static let keyFlagsMask: Int = 0x0000FFFF
        /// Bitmask to extract key state from flags (bits 8-15)
        static let keyStateMask: Int = 0xFF00
        /// Key-down state value
        static let keyDownState: Int = 0x0A
        /// NX_KEYTYPE_BRIGHTNESS_UP
        static let brightnessUp: Int = 2
        /// NX_KEYTYPE_BRIGHTNESS_DOWN
        static let brightnessDown: Int = 3
    }

    /// 1/32 of full range: 16 SDR steps + 16 XDR steps.
    static let brightnessStepValue: Float = 1.0 / 32.0

    /// Whether the callback should decide/return for this event.
    private enum EventDecision: Sendable { case passThrough, swallow }

    var brightnessStep: Float { Self.brightnessStepValue }

    // Instance state. The CGEventTap C callback recovers `self` from its
    // refcon (`userInfo`) and reaches this state via `MainActor.assumeIsolated`
    // — the tap's run-loop source is on the main run loop, so the callback
    // already runs on the main thread. No shared static state / locks needed.
    var intercepting: Bool = false
    var onBrightnessKey: BrightnessKeyHandler?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func start() {
        guard eventTap == nil else { return }

        // CGEventTap requires accessibility permissions
        guard AXIsProcessTrusted() else {
            logger.info("Accessibility NOT granted — prompting user")
            // kAXTrustedCheckOptionPrompt is a global `var` in ApplicationServices which
            // strict concurrency flags as non-Sendable. The underlying CFString value is
            // documented and stable across OS versions, so we reference it by literal.
            let options = ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
            return
        }
        logger.info("Accessibility granted")

        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << MediaKey.sysDefinedEventType)

        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passRetained(event) }
                let manager = Unmanaged<BrightnessKeyManager>.fromOpaque(userInfo).takeUnretainedValue()
                // The tap's run-loop source lives on the main run loop, so this
                // fires on the main thread — assume the main actor to touch
                // `manager`'s isolated state directly.
                let decision = MainActor.assumeIsolated {
                    manager.handleEvent(type: type, event: event)
                }
                switch decision {
                case .passThrough: return Unmanaged.passRetained(event)
                case .swallow: return nil
                }
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let tap else {
            logger.error("Failed to create event tap — accessibility permissions needed")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        logger.info("Event tap started")
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
        }
        eventTap = nil
        runLoopSource = nil
        logger.info("Event tap stopped")
    }

    // Runs on the main actor (see the callback in `start()`), returning a
    // decision the C callback translates into swallow (nil) / pass-through.
    private func handleEvent(type: CGEventType, event: CGEvent) -> EventDecision {
        // The system silently disables taps whose callbacks run too slowly
        // (or on user-input interference). Without re-enabling here, every
        // subsequent brightness key flows through natively — the native OSD
        // reappears and ours goes dead until app restart.
        if Self.isTapDisabledEvent(type) {
            logger.error("Event tap disabled by system (type \(type.rawValue, privacy: .public)) — re-enabling")
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return .swallow
        }

        guard type.rawValue == MediaKey.sysDefinedEventType,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == MediaKey.mediaKeySubtype else {
            return .passThrough
        }

        let keyCode = Int((nsEvent.data1 & MediaKey.keyCodeMask) >> 16)
        let keyFlags = nsEvent.data1 & MediaKey.keyFlagsMask
        let keyState = (keyFlags & MediaKey.keyStateMask) >> 8
        let isKeyDown = keyState == MediaKey.keyDownState

        guard keyCode == MediaKey.brightnessUp || keyCode == MediaKey.brightnessDown else {
            return .passThrough
        }

        logger.debug("Brightness key: keyCode=\(keyCode, privacy: .public) isKeyDown=\(isKeyDown, privacy: .public) intercepting=\(self.intercepting, privacy: .public)")

        guard intercepting else {
            return .passThrough
        }

        // Swallow key-up too while intercepting, otherwise the native OSD flickers.
        guard isKeyDown else { return .swallow }

        let isUp = keyCode == MediaKey.brightnessUp
        if let handler = onBrightnessKey {
            // Defer the handler to the next main-actor turn so this tap
            // callback returns immediately — a slow callback gets the tap
            // disabled by the system.
            Task { @MainActor in handler(isUp) }
        }

        return .swallow
    }

    /// Internal (not private) for unit testing.
    static func isTapDisabledEvent(_ type: CGEventType) -> Bool {
        type == .tapDisabledByTimeout || type == .tapDisabledByUserInput
    }
}
