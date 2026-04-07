//
//  IntegrityChecker.swift
//  Fullbright
//
//  Anti-tampering checks: bundle identity, code signature, and debugger detection.
//

import Foundation
import Security
import Darwin

struct IntegrityChecker: IntegrityChecking, Sendable {
    init() {}

    /// Returns true if all integrity checks pass (bundle ID, code signature, debugger).
    /// SecStaticCodeCheckValidity is synchronous and can take tens of
    /// milliseconds on first call, so we offload it to a utility-priority
    /// detached task to keep the main actor responsive during launch.
    func passesAllChecks() async -> Bool {
        await Task.detached(priority: .utility) {
            guard Bundle.main.bundleIdentifier == AppIdentifier.expectedBundleIdentifier else {
                return false
            }

            if !Self.isCodeSignatureValid() {
                return false
            }

            if Self.isBeingDebugged() && !Self.isDebugBuild() {
                return false
            }

            return true
        }.value
    }

    // MARK: - Code Signature

    private static func isCodeSignatureValid() -> Bool {
        var staticCode: SecStaticCode?
        let bundleURL = Bundle.main.bundleURL as CFURL

        guard SecStaticCodeCreateWithPath(bundleURL, [], &staticCode) == errSecSuccess,
              let code = staticCode else {
            return false
        }

        return SecStaticCodeCheckValidity(code, [], nil) == errSecSuccess
    }

    // MARK: - Debugger Detection

    private static func isBeingDebugged() -> Bool {
        // Method 1: P_TRACED flag check
        var info = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var size = MemoryLayout<kinfo_proc>.size

        let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)

        if result == 0 && (info.kp_proc.p_flag & P_TRACED) != 0 {
            return true
        }

        // Method 2: Check for common debugging environment variables
        let debugEnvVars = ["DYLD_INSERT_LIBRARIES"]
        for envVar in debugEnvVars {
            if getenv(envVar) != nil {
                return true
            }
        }

        return false
    }

    // MARK: - Build Type

    private static func isDebugBuild() -> Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}
