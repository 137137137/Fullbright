//
//  IntegrityChecking.swift
//  Fullbright
//
//  Integrity verification protocol.
//

import Foundation

protocol IntegrityChecking: Sendable {
    func passesAllChecks() -> Bool
}
