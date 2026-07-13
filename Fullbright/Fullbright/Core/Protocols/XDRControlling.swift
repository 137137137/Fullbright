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

    /// True when the previous session ended without restoring the display
    /// (crash, power-button reset). Used to suppress automatic XDR
    /// enabling for this session — if XDR contributed to the bad exit,
    /// auto-enabling would re-trigger it on every login. Manual enabling
    /// still works.
    var previousSessionEndedDirty: Bool { get }

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
