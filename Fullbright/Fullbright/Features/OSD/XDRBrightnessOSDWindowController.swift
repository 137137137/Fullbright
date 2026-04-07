//
//  XDRBrightnessOSDWindowController.swift
//  Fullbright
//

import AppKit
import SwiftUI
import os

private let logger = Logger(subsystem: AppIdentifier.serviceID, category: "OSD")

// MARK: - OSD Window

@MainActor
final class XDRBrightnessOSDWindow: NSPanel, NSWindowDelegate {
    convenience init(contentSwiftUIView: NSView) {
        self.init(
            contentRect: .zero,
            styleMask: [.fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: true,
            screen: NSScreen.main
        )
        contentView = contentSwiftUIView
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        collectionBehavior = [.stationary, .canJoinAllSpaces, .ignoresCycle, .fullScreenDisallowsTiling]
        ignoresMouseEvents = false
        setAccessibilityRole(.popover)
        setAccessibilitySubrole(.unknown)

        backgroundColor = .clear
        contentView?.layer?.backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        delegate = self
    }

    @objc dynamic var hovering = false

    private var fadeTask: Task<Void, Never>?
    private var hoverTrackingArea: NSTrackingArea?

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        super.mouseExited(with: event)
    }

    func hideOSD() {
        fadeTask?.cancel()
        fadeTask = nil
        removeHoverTrackingArea()
        contentView?.superview?.alphaValue = 0.0
        close()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { true }

    func showOSD(on screen: NSScreen?, fadeAfterMs: Int = 2000) {
        guard let screen else { return }

        let vf = screen.visibleFrame
        let contentSize = frame.size
        let x = vf.maxX - contentSize.width - OSDLayout.windowTrailingMargin
        let y = vf.maxY - contentSize.height - OSDLayout.windowTopMargin
        setFrame(NSRect(origin: NSPoint(x: x, y: y), size: contentSize), display: true)

        // If the size isn't known yet (first show), reposition after layout
        if contentSize.width <= 1 {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(10))
                guard let self, let size = self.contentView?.fittingSize else { return }
                self.setContentSize(size)
                let x = vf.maxX - size.width - OSDLayout.windowTrailingMargin
                let y = vf.maxY - size.height - OSDLayout.windowTopMargin
                self.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: true)
            }
        }

        contentView?.superview?.alphaValue = 1
        orderFrontRegardless()
        addHoverTrackingArea()

        fadeTask?.cancel()
        fadeTask = nil

        guard fadeAfterMs > 0 else { return }

        fadeTask = Task { @MainActor [weak self] in
            // Wait before starting fade
            try? await Task.sleep(for: .milliseconds(fadeAfterMs))
            guard !Task.isCancelled, let self, self.isVisible else { return }

            // If hovering, wait until the user stops hovering
            while self.hovering {
                try? await Task.sleep(for: .milliseconds(fadeAfterMs))
                guard !Task.isCancelled else { return }
            }

            // Fade out
            self.ignoresMouseEvents = true
            await NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 1.0
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.contentView?.superview?.animator().alphaValue = 0.01
            }
            guard !Task.isCancelled else { return }
            self.contentView?.superview?.alphaValue = 0

            // orderOut(), not close() — close() + isReleasedWhenClosed=false
            // leaves a stale window that doesn't replay on next show.
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            self.ignoresMouseEvents = false
            self.orderOut(nil)
            self.removeHoverTrackingArea()
        }
    }

    func windowWillClose(_ notification: Notification) {
        fadeTask?.cancel()
        fadeTask = nil
        removeHoverTrackingArea()
        ignoresMouseEvents = false
    }

    // MARK: - Hover Tracking

    private func addHoverTrackingArea() {
        guard let view = contentView else { return }
        removeHoverTrackingArea()
        let opts: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        let area = NSTrackingArea(rect: view.bounds, options: opts, owner: self, userInfo: nil)
        view.addTrackingArea(area)
        hoverTrackingArea = area
    }

    private func removeHoverTrackingArea() {
        if let area = hoverTrackingArea, let view = contentView {
            view.removeTrackingArea(area)
        }
        hoverTrackingArea = nil
        hovering = false
    }

}

// MARK: - OSD Window Controller

@MainActor
final class XDRBrightnessOSDWindowController {
    private let xdrController: any XDRControlling

    init(xdrController: any XDRControlling) {
        self.xdrController = xdrController
    }

    private static let nitsFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()

    private let osdState = XDRBrightnessOSDState()
    private var window: XDRBrightnessOSDWindow?

    func show(
        value: Float? = nil,
        text: String? = nil,
        leadingLabel: String? = nil,
        image: String = "sun.max.fill",
        leadingIcon: String? = "sun.min.fill",
        locked: Bool = false,
        tip: String? = nil,
        onChange: ((Float) -> Void)? = nil
    ) {
        osdState.value = value ?? xdrController.brightness
        logger.debug("show() called — brightness=\(self.xdrController.brightness, privacy: .public), nits=\(self.xdrController.currentNits, privacy: .public), osdValue=\(self.osdState.value, privacy: .public)")
        osdState.image = image
        osdState.leadingIcon = leadingIcon
        osdState.locked = locked
        osdState.tip = tip

        let nits = xdrController.currentNits
        let nitsText = "\(Self.nitsFormatter.string(from: NSNumber(value: nits)) ?? "\(nits)") nits"
        osdState.text = text ?? nitsText
        let rangeText = nits > Int(BrightnessNitsConverter.sdrMaxNits) ? "Display (XDR Range)" : "Display (SDR Range)"
        osdState.leadingLabel = leadingLabel ?? rangeText

        osdState.onChange = onChange ?? { [xdrController] newValue in
            xdrController.adjustBrightness(delta: newValue - xdrController.brightness)
        }

        if window == nil { createWindow() }
        window?.showOSD(on: NSScreen.main)
    }

    private func createWindow() {
        let view = NSHostingView(rootView: XDRBrightnessOSDView(osd: osdState))
        let panel = XDRBrightnessOSDWindow(contentSwiftUIView: view)
        self.window = panel
    }
}
