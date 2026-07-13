//
//  HDRWindow.swift
//  Fullbright
//
//  HDR overlay window factory. A 2x2 borderless window at
//  CGShieldingWindowLevel hosting an MTKView that continuously presents
//  EDR-white drawables (clear color > 1.0 in extended linear sRGB) at a
//  low frame rate. Actually presenting frames — not just setting a layer
//  background color — is what reliably makes the window server grant EDR
//  headroom on macOS 26+.
//

import AppKit
import MetalKit
import QuartzCore
import os

private let logger = Logger(subsystem: AppIdentifier.serviceID, category: "HDRWindow")

/// Undocumented NSWindow.StyleMask for a borderless utility window.
private let hdrStyleMask = NSWindow.StyleMask(rawValue: 0x8000)

// MARK: - EDR Trigger View

/// Renders clear-only frames whose clear color sits above 1.0 in extended
/// linear sRGB, keeping the display's EDR pipeline engaged.
@MainActor
private final class EDRTriggerView: MTKView, MTKViewDelegate {
    private var commandQueue: MTLCommandQueue?

    init?(frame: CGRect, edrValue: Double) {
        guard let metalDevice = MTLCreateSystemDefaultDevice(),
              let queue = metalDevice.makeCommandQueue(),
              let colorSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) else {
            return nil
        }
        super.init(frame: frame, device: metalDevice)
        commandQueue = queue

        autoResizeDrawable = false
        drawableSize = CGSize(width: 2, height: 2)
        colorPixelFormat = .rgba16Float
        colorspace = colorSpace
        clearColor = MTLClearColorMake(edrValue, edrValue, edrValue, 1.0)
        preferredFramesPerSecond = 5
        delegate = self

        if let metalLayer = layer as? CAMetalLayer {
            metalLayer.wantsExtendedDynamicRangeContent = true
            metalLayer.pixelFormat = .rgba16Float
        }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func draw(in view: MTKView) {
        guard let commandQueue,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor),
              let drawable = view.currentDrawable else {
            return
        }
        // Clear-only pass; the clear color is the EDR content.
        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
}

// MARK: - Factory

enum HDRWindowFactory {
    @MainActor
    static func makeWindow(for screen: NSScreen?) -> NSWindow? {
        guard let targetScreen = screen ?? NSScreen.deepest ?? NSScreen.main else { return nil }

        let potentialEDR = targetScreen.maximumPotentialExtendedDynamicRangeColorComponentValue
        let edrValue = Double(max(1.5, potentialEDR))

        // Tucked into the bottom-left corner of the target screen where
        // the 2x2 EDR-white patch is effectively invisible.
        let origin = targetScreen.frame.origin
        let window = NSWindow(
            contentRect: NSRect(x: origin.x, y: origin.y, width: 2, height: 2),
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
        window.isOpaque = false
        window.hasShadow = false
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none

        if let triggerView = EDRTriggerView(frame: NSRect(x: 0, y: 0, width: 2, height: 2), edrValue: edrValue) {
            window.contentView = triggerView
            triggerView.draw()
        } else {
            // No Metal device (VM, unusual GPU): fall back to a non-presenting
            // EDR-tagged layer, which engages headroom on some configurations.
            logger.warning("No Metal device — falling back to EDR-tagged layer without presentation")
            guard let contentView = window.contentView,
                  let colorSpace = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020) else { return nil }
            contentView.wantsLayer = true
            let metalLayer = CAMetalLayer()
            metalLayer.wantsExtendedDynamicRangeContent = true
            metalLayer.pixelFormat = .rgba16Float
            metalLayer.colorspace = colorSpace
            metalLayer.edrMetadata = CAEDRMetadata.hdr10(
                minLuminance: 0.5,
                maxLuminance: Float(potentialEDR) * 100.0,
                opticalOutputScale: 100.0
            )
            metalLayer.backgroundColor = CGColor(colorSpace: colorSpace, components: [edrValue, edrValue, edrValue, 1.0])
            metalLayer.opacity = 0.1
            contentView.layer = metalLayer
            window.alphaValue = 0.1
        }

        window.orderFrontRegardless()
        return window
    }
}
