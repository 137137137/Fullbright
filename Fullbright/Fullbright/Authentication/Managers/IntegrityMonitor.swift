//
//  IntegrityMonitor.swift
//  Fullbright
//
//  Periodic integrity-check loop, extracted from SecureAuthenticationManager.
//
//  Owns a single long-running Task that sleeps for `interval`, calls
//  `IntegrityChecking.passesAllChecks()`, and invokes `onFailure` if the
//  check fails. A `nonisolated deinit` cancels the MainActor-isolated Task
//  property directly (Task is Sendable), so the loop is torn down from any
//  context, including during deinit.
//

import Foundation

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

    /// A `nonisolated deinit` can cancel this MainActor-isolated `Task`
    /// property directly (Task is Sendable), so the loop is torn down from
    /// any context, including during deinit.
    private var task: Task<Void, Never>?

    init(checker: any IntegrityChecking) {
        self.checker = checker
    }

    nonisolated deinit {
        task?.cancel()
    }

    func start(interval: Duration, onFailure: @MainActor @Sendable @escaping () async -> Void) {
        let checker = self.checker
        task?.cancel()
        task = Task { @MainActor in
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
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
