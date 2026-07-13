//
//  DisplayLifecycleObserving.swift
//  Fullbright
//
//  Display sleep/wake and configuration-change events, abstracted from
//  NSWorkspace/NSApplication notifications for testability.
//

import Foundation

@MainActor
protocol DisplayLifecycleObserving: AnyObject {
    /// Screens are going to sleep (lid close, display sleep).
    var onScreensSleep: (@MainActor () -> Void)? { get set }
    /// System woke from sleep.
    var onWake: (@MainActor () -> Void)? { get set }
    /// Display configuration changed (resolution, arrangement, connect/
    /// disconnect). Delivered debounced — bursts collapse to one call.
    var onDisplayParametersChanged: (@MainActor () -> Void)? { get set }

    func start()
    func stop()
}
