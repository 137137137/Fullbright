//
//  IntegrityMonitor.swift
//  Fullbright
//
//  Periodic integrity-check loop, extracted from SecureAuthenticationManager.
//
//  Owns a single long-running Task that sleeps for `interval`, calls
//  `IntegrityChecking.passesAllChecks()`, and invokes `onFailure` if the
//  check fails. Uses the OSAllocatedUnfairLock<Task?> + nonisolated deinit
//  pattern established elsewhere so the loop is cancellable from any
//  context, including during deinit.
//

import Foundation
import os

@MainActor
protocol IntegrityMonitoring: AnyObject {
    /// Begins the monitoring loop. Calling `start` while already running
    /// cancels the previous loop and begins a new one. Cheap to call.
    func start(interval: Duration, onFailure: @MainActor @Sendable @escaping () async -> Void)

    /// Cancels the current loop. Idempotent.
    func stop()
}

@MainActor
final class IntegrityMonitor: IntegrityMonitoring {
    private let checker: any IntegrityChecking

    /// See SecureAuthenticationManager.integrityCheckTaskLock for the
    /// rationale behind wrapping a Task in OSAllocatedUnfairLock.
    private let taskLock = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)

    init(checker: any IntegrityChecking) {
        self.checker = checker
    }

    nonisolated deinit {
        taskLock.withLock { $0?.cancel() }
    }

    func start(interval: Duration, onFailure: @MainActor @Sendable @escaping () async -> Void) {
        let checker = self.checker
        let task = Task { @MainActor in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                if await !checker.passesAllChecks() {
                    await onFailure()
                }
            }
        }
        taskLock.withLock { existing in
            existing?.cancel()
            existing = task
        }
    }

    func stop() {
        taskLock.withLock { existing in
            existing?.cancel()
            existing = nil
        }
    }
}
