//
//  IntegrityChecking.swift
//  Fullbright
//
//  Integrity verification protocol.
//

import Foundation

protocol IntegrityChecking: Sendable {
    /// Runs bundle, code-signature, and debugger checks. Async because
    /// SecStaticCodeCheckValidity is a blocking Security-framework call that
    /// should not run on the main actor during app startup.
    func passesAllChecks() async -> Bool
}
