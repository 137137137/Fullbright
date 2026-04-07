//
//  OnboardingWindowController.swift
//  Fullbright
//

import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSWindowController {
    init(onComplete: @escaping () -> Void = {}) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: WindowSize.settingsWidth, height: WindowSize.settingsHeight),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Fullbright"
        window.center()

        super.init(window: window)

        let contentView = NSHostingView(rootView: OnboardingSimpleView { [weak window] in
            onComplete()
            window?.close()
        })
        window.contentView = contentView
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
