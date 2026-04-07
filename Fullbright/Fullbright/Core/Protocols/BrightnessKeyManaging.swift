//
//  BrightnessKeyManaging.swift
//  Fullbright
//
//  Brightness key interception protocol.
//

import Foundation

/// true = up, false = down. @Sendable so the C event-tap callback can hop
/// it to the main actor.
typealias BrightnessKeyHandler = @MainActor @Sendable (_ isUp: Bool) -> Void

@MainActor
protocol BrightnessKeyManaging: AnyObject {
    var brightnessStep: Float { get }
    var intercepting: Bool { get set }
    var onBrightnessKey: BrightnessKeyHandler? { get set }
    func start()
    func stop()
}
