//
//  NightShiftManaging.swift
//  Fullbright
//
//  Night Shift management protocol.
//

import Foundation

@MainActor
protocol NightShiftManaging {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool)
}
