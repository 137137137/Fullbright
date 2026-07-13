//
//  LaunchAtLoginManaging.swift
//  Fullbright
//
//  Launch-at-login protocol.
//

import Foundation

protocol LaunchAtLoginManaging: Sendable {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}
