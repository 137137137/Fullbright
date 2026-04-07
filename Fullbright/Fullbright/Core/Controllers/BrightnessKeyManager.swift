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

    // The CGEventTap callback is a plain C function running on an event-tap
    // thread, so the two pieces of state it needs live in static locks.

    private static let interceptingState = OSAllocatedUnfairLock(initialState: false)
    private static let keyHandlerState = OSAllocatedUnfairLock<BrightnessKeyHandler?>(initialState: nil)

    private static var isIntercepting: Bool {
        get { interceptingState.withLock { $0 } }
        set { interceptingState.withLock { $0 = newValue } }
    }

    private static var currentKeyHandler: BrightnessKeyHandler? {
        get { keyHandlerState.withLock { $0 } }
        set { keyHandlerState.withLock { $0 = newValue } }
    }

    var brightnessStep: Float { Self.brightnessStepValue }

    var intercepting: Bool {
        get { Self.isIntercepting }
        set { Self.isIntercepting = newValue }
    }

    var onBrightnessKey: BrightnessKeyHandler? {
        get { Self.currentKeyHandler }
        set { Self.currentKeyHandler = newValue }
    }

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
            callback: { _, type, event, _ in
                BrightnessKeyManager.handleEvent(type: type, event: event)
            },
            userInfo: nil
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

    // Called off the main actor on the event-tap thread.
    // Return nil to swallow the event, passRetained to pass it through.
    private static func handleEvent(
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        guard type.rawValue == MediaKey.sysDefinedEventType,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == MediaKey.mediaKeySubtype else {
            return Unmanaged.passRetained(event)
        }

        let keyCode = Int((nsEvent.data1 & MediaKey.keyCodeMask) >> 16)
        let keyFlags = nsEvent.data1 & MediaKey.keyFlagsMask
        let keyState = (keyFlags & MediaKey.keyStateMask) >> 8
        let isKeyDown = keyState == MediaKey.keyDownState

        guard keyCode == MediaKey.brightnessUp || keyCode == MediaKey.brightnessDown else {
            return Unmanaged.passRetained(event)
        }

        let intercepting = isIntercepting
        logger.debug("Brightness key: keyCode=\(keyCode, privacy: .public) isKeyDown=\(isKeyDown, privacy: .public) intercepting=\(intercepting, privacy: .public)")

        guard intercepting else {
            return Unmanaged.passRetained(event)
        }

        // Swallow key-up too while intercepting, otherwise the native OSD flickers.
        guard isKeyDown else { return nil }

        let isUp = keyCode == MediaKey.brightnessUp
        if let handler = currentKeyHandler {
            Task { @MainActor in
                handler(isUp)
            }
        }

        return nil
    }
}
