//
//  HDRWindow.swift
//  Fullbright
//
//  HDR overlay window factory (Branch B — every selector verified by instruction trace).
//  2x2 borderless window at CGShieldingWindowLevel with CAMetalLayer in
//  ExtendedLinearITUR_2020 to trigger EDR headroom allocation.
//

import AppKit
import QuartzCore

/// Undocumented NSWindow.StyleMask for a borderless utility window.
private let hdrStyleMask = NSWindow.StyleMask(rawValue: 0x8000)

enum HDRWindowFactory {
    @MainActor
    static func makeWindow(for screen: NSScreen?) -> NSWindow? {
        guard let targetScreen = screen ?? NSScreen.deepest ?? NSScreen.main else { return nil }

        let potentialEDR = targetScreen.maximumPotentialExtendedDynamicRangeColorComponentValue
        let maxNits = Float(potentialEDR) * 100.0

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 2, height: 2),
            styleMask: hdrStyleMask,
            backing: .buffered,
            defer: false,
            screen: targetScreen
        )

        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.sharingType = .none
        window.ignoresMouseEvents = true
        window.setAccessibilityRole(.popover)
        window.setAccessibilitySubrole(.unknown)
        window.backgroundColor = .clear

        guard let cv = window.contentView else { return nil }
        cv.wantsLayer = true

        let ml = CAMetalLayer()
        ml.wantsExtendedDynamicRangeContent = true
        ml.pixelFormat = .rgba16Float

        guard let cs = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020) else { return nil }
        ml.colorspace = cs

        ml.edrMetadata = CAEDRMetadata.hdr10(minLuminance: 0.5, maxLuminance: maxNits, opticalOutputScale: 100.0)

        let edrVal = CGFloat(potentialEDR)
        ml.backgroundColor = CGColor(colorSpace: cs, components: [edrVal, edrVal, edrVal, 1.0])

        ml.opacity = 0.1
        cv.layer = ml

        window.isOpaque = false
        window.hasShadow = false
        window.styleMask = hdrStyleMask
        window.hidesOnDeactivate = false
        cv.alphaValue = 1.0
        window.alphaValue = 0.1
        window.orderFrontRegardless()

        return window
    }
}
