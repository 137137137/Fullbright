//
//  XDRControlling.swift
//  Fullbright
//
//  XDR brightness controller protocol.
//

import Foundation

@MainActor
protocol XDRControlling: AnyObject {
    var isEnabled: Bool { get }
    var brightness: Float { get }
    var currentNits: Int { get }

    var isXDRSupported: Bool { get }
    @discardableResult func enableXDR() -> Bool

    /// Turn XDR off. The default (non-immediate) path eases the boosted
    /// gamma back to the pre-XDR level before restoring the backlight —
    /// the mirror of the enable flash guard. `immediate: true` tears down
    /// synchronously (app termination, broken gamma writes).
    @discardableResult func disableXDR(immediate: Bool) -> Bool

    func adjustBrightness(delta: Float)
}

extension XDRControlling {
    @discardableResult
    func disableXDR() -> Bool {
        disableXDR(immediate: false)
    }
}
