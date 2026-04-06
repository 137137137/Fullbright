//
//  BrightnessKeyManaging.swift
//  Fullbright
//
//  Brightness key interception protocol.
//

import Foundation

@MainActor
protocol BrightnessKeyManaging: AnyObject {
    var onBrightnessChange: (() -> Void)? { get set }
    /// Whether brightness key events are intercepted (suppressing native OSD).
    var intercepting: Bool { get set }
    /// Closure invoked from the event tap callback to adjust brightness.
    var adjustBrightnessAction: ((Float) -> Void)? { get set }
    func start()
    func stop()
}
