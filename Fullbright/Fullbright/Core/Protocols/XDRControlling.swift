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
    @discardableResult func disableXDR() -> Bool
    func adjustBrightness(delta: Float)
}
