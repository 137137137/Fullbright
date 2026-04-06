//
//  LaunchAtLoginManaging.swift
//  Fullbright
//
//  Launch-at-login protocol.
//

import Foundation

protocol LaunchAtLoginManaging {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}
