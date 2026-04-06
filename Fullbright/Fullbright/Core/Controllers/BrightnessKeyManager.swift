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
    static let shared = BrightnessKeyManager()

    // MARK: - Media Key Constants (IOKit NX_* values)

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

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Thread-safe flag for the C callback to check synchronously.
    /// When true, brightness key events are swallowed (native OSD suppressed).
    /// Protected by OSAllocatedUnfairLock because the C event tap callback reads
    /// this off the main actor while @MainActor methods write it.
    static let interceptingLock = OSAllocatedUnfairLock(initialState: false)

    static var intercepting: Bool {
        get { interceptingLock.withLock { $0 } }
        set { interceptingLock.withLock { $0 = newValue } }
    }

    /// Lock-protected closure for the C callback to invoke brightness adjustments
    /// without directly referencing XDRController.shared. Set by AppCoordinator at start().
    static let adjustBrightnessLock = OSAllocatedUnfairLock<((Float) -> Void)?>(initialState: nil)

    static var adjustBrightnessAction: ((Float) -> Void)? {
        get { adjustBrightnessLock.withLock { $0 } }
        set { adjustBrightnessLock.withLock { $0 = newValue } }
    }

    /// Step size for brightness adjustment (1/32 of full range — 16 SDR steps + 16 XDR steps)
    private let brightnessStep: Float = 1.0 / 32.0

    // MARK: - Protocol-conforming instance wrappers for static lock-protected state.
    // The C event tap callback requires static access; these provide protocol-based DI.

    var intercepting: Bool {
        get { Self.intercepting }
        set { Self.intercepting = newValue }
    }

    var adjustBrightnessAction: ((Float) -> Void)? {
        get { Self.adjustBrightnessAction }
        set { Self.adjustBrightnessAction = newValue }
    }

    /// Callback for when brightness changes (to show OSD)
    var onBrightnessChange: (() -> Void)?

    func start() {
        guard eventTap == nil else { return }

        // CGEventTap requires accessibility permissions
        guard AXIsProcessTrusted() else {
            logger.info("Accessibility NOT granted — prompting user")
            let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
            return
        }
        logger.info("Accessibility granted")

        // Create the event tap on a background thread (CGEventTap callback is C-convention)
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << MediaKey.sysDefinedEventType)

        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, userInfo in
                return BrightnessKeyManager.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: nil
        )

        guard let tap = tap else {
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

    // MARK: - Event Handling (C callback, not on MainActor)

    private static func handleEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        // Handle NX_SYSDEFINED events (media keys)
        guard type.rawValue == MediaKey.sysDefinedEventType else {
            return Unmanaged.passRetained(event)
        }

        guard let nsEvent = NSEvent(cgEvent: event) else {
            return Unmanaged.passRetained(event)
        }

        guard nsEvent.subtype.rawValue == MediaKey.mediaKeySubtype else {
            return Unmanaged.passRetained(event)
        }

        let keyCode = Int((nsEvent.data1 & MediaKey.keyCodeMask) >> 16)
        let keyFlags = nsEvent.data1 & MediaKey.keyFlagsMask
        let keyState = (keyFlags & MediaKey.keyStateMask) >> 8
        let isKeyDown = keyState == MediaKey.keyDownState

        guard keyCode == MediaKey.brightnessUp || keyCode == MediaKey.brightnessDown else {
            return Unmanaged.passRetained(event)
        }

        logger.debug("Brightness key detected: keyCode=\(keyCode, privacy: .public), isKeyDown=\(isKeyDown, privacy: .public), intercepting=\(BrightnessKeyManager.intercepting, privacy: .public)")

        guard isKeyDown else {
            // Swallow key-up events too when intercepting to prevent native OSD
            return BrightnessKeyManager.intercepting ? nil : Unmanaged.passRetained(event)
        }

        guard BrightnessKeyManager.intercepting else {
            logger.debug("NOT intercepting — passing event to system")
            return Unmanaged.passRetained(event)
        }

        let isBrightnessUp = keyCode == MediaKey.brightnessUp

        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let manager = BrightnessKeyManager.shared
                let delta: Float = isBrightnessUp ? manager.brightnessStep : -manager.brightnessStep
                BrightnessKeyManager.adjustBrightnessAction?(delta)
                manager.onBrightnessChange?()
            }
        }

        // Always swallow the event to suppress native macOS OSD
        return nil
    }
}
