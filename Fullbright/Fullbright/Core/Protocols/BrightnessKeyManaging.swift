//
//  BrightnessKeyManaging.swift
//  Fullbright
//
//  Brightness key interception protocol.
//

import Foundation

/// Closure invoked when a brightness key is pressed.
/// - Parameter isUp: `true` for brightness-up, `false` for brightness-down.
///
/// Marked `@MainActor @Sendable` so it can be stored in a thread-safe lock
/// and invoked from the (non-isolated) C event-tap callback by hopping to
/// the main actor.
typealias BrightnessKeyHandler = @MainActor @Sendable (_ isUp: Bool) -> Void

@MainActor
protocol BrightnessKeyManaging: AnyObject {
    /// Brightness delta produced by a single key press.
    /// Exposed so the consumer can decide how to apply it.
    var brightnessStep: Float { get }

    /// Whether brightness key events are intercepted (suppressing native OSD).
    var intercepting: Bool { get set }

    /// Handler invoked from the event-tap callback when a brightness key is pressed.
    var onBrightnessKey: BrightnessKeyHandler? { get set }

    func start()
    func stop()
}
