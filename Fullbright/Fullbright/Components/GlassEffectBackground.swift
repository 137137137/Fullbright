//
//  GlassEffectBackground.swift
//  Fullbright
//
//  Private NSGlassEffectView wrapper, matching Lunar's approach (variant 6).
//  Used as a background — SwiftUI content is overlaid via .overlay() or ZStack,
//  NOT embedded inside the NSView, so SwiftUI state updates propagate normally.
//

import SwiftUI
import AppKit

struct GlassEffectBackground: NSViewRepresentable {
    var variant: Int? = nil
    var scrimState: Int? = nil
    var subduedState: Int? = nil
    var interactionState: Int? = nil
    var contentLensing: Int? = nil
    var adaptiveAppearance: Int? = nil
    var useReducedShadowRadius: Int? = nil
    var style: NSGlassEffectView.Style? = nil
    var tint: NSColor? = nil
    var cornerRadius: CGFloat? = nil

    func makeNSView(context: Context) -> NSView {
        guard let glassType = NSClassFromString("NSGlassEffectView") as? NSView.Type else {
            return NSView()
        }
        let nsView = glassType.init(frame: .zero)
        configureView(nsView)
        context.coordinator.lastConfig = configSnapshot
        return nsView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let current = configSnapshot
        guard current != context.coordinator.lastConfig else { return }
        configureView(nsView)
        context.coordinator.lastConfig = current
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastConfig: ConfigSnapshot?
    }

    struct ConfigSnapshot: Equatable {
        let variant: Int?
        let scrimState: Int?
        let subduedState: Int?
        let interactionState: Int?
        let contentLensing: Int?
        let adaptiveAppearance: Int?
        let useReducedShadowRadius: Int?
        let cornerRadius: CGFloat?
        let styleRawValue: Int?
        let tintHash: Int?
    }

    private var configSnapshot: ConfigSnapshot {
        ConfigSnapshot(
            variant: variant,
            scrimState: scrimState,
            subduedState: subduedState,
            interactionState: interactionState,
            contentLensing: contentLensing,
            adaptiveAppearance: adaptiveAppearance,
            useReducedShadowRadius: useReducedShadowRadius,
            cornerRadius: cornerRadius,
            styleRawValue: style.map { Int($0.rawValue) },
            tintHash: tint?.hash
        )
    }

    private func configureView(_ nsView: NSView) {
        if let variant { nsView.setValue(variant, forKey: "_variant") }
        if let interactionState { nsView.setValue(interactionState, forKey: "_interactionState") }
        if let contentLensing { nsView.setValue(contentLensing, forKey: "_contentLensing") }
        if let adaptiveAppearance { nsView.setValue(adaptiveAppearance, forKey: "_adaptiveAppearance") }
        if let useReducedShadowRadius { nsView.setValue(useReducedShadowRadius, forKey: "_useReducedShadowRadius") }
        if let scrimState { nsView.setValue(scrimState, forKey: "_scrimState") }
        if let subduedState { nsView.setValue(subduedState, forKey: "_subduedState") }
        if let style { (nsView as? NSGlassEffectView)?.style = style }
        if let tint { nsView.setValue(tint, forKey: "tintColor") }
        if let cornerRadius { nsView.setValue(cornerRadius, forKey: "cornerRadius") }
    }
}
