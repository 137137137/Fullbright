//
//  AppLifecycle.swift
//  Fullbright
//
//  Abstraction over app-level platform actions so ViewModels don't
//  depend on AppKit.
//

import Foundation

@MainActor
protocol AppLifecycle: Sendable {
    func terminate()

    /// Bring the app to the foreground and raise its frontmost standard
    /// window. Menu-bar (accessory) apps don't get activated when they
    /// open a window, so anything opened from the status item otherwise
    /// appears behind other apps' windows.
    func activate()
}
