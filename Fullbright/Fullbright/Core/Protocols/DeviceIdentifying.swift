//
//  DeviceIdentifying.swift
//  Fullbright
//
//  Device identification protocol.
//

import Foundation

protocol DeviceIdentifying: Sendable {
    var secureIdentifier: String { get }
}
