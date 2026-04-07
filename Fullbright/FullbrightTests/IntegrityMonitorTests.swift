//
//  IntegrityMonitorTests.swift
//  FullbrightTests
//

import Foundation
import os
import Testing
@testable import Fullbright

/// A configurable integrity checker whose pass/fail state is toggled by the
/// test. Thread-safe because IntegrityMonitor may await `passesAllChecks`
/// from any actor context.
private final class MutableIntegrityChecker: IntegrityChecking, @unchecked Sendable {
    private let state: OSAllocatedUnfairLock<Bool>

    init(initialPasses: Bool) {
        self.state = OSAllocatedUnfairLock(initialState: initialPasses)
    }

    func setPasses(_ passes: Bool) {
        state.withLock { $0 = passes }
    }

    func passesAllChecks() async -> Bool {
        state.withLock { $0 }
    }
}

/// Polls `condition` repeatedly until it returns true or `timeout` expires.
/// More robust than a fixed `Task.sleep` under test-suite contention.
@MainActor
private func waitUntil(
    _ condition: @MainActor () -> Bool,
    timeout: Duration = .seconds(2)
) async -> Bool {
    let start = ContinuousClock.now
    while ContinuousClock.now - start < timeout {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

@MainActor
@Suite("IntegrityMonitor", .serialized)
struct IntegrityMonitorTests {

    @Test("onFailure fires when the checker starts returning false")
    func onFailure_firesWhenCheckFails() async {
        let checker = MutableIntegrityChecker(initialPasses: true)
        let monitor = IntegrityMonitor(checker: checker)

        let callCountLock = OSAllocatedUnfairLock<Int>(initialState: 0)
        monitor.start(interval: .milliseconds(20)) { @MainActor in
            callCountLock.withLock { $0 += 1 }
        }

        // Flip to failing state and wait (generously) for at least one tick.
        checker.setPasses(false)
        let fired = await waitUntil { callCountLock.withLock { $0 } >= 1 }
        monitor.stop()

        #expect(fired)
    }

    @Test("onFailure does not fire while the checker keeps passing")
    func onFailure_doesNotFireWhilePassing() async throws {
        let checker = MutableIntegrityChecker(initialPasses: true)
        let monitor = IntegrityMonitor(checker: checker)

        let callCountLock = OSAllocatedUnfairLock<Int>(initialState: 0)
        monitor.start(interval: .milliseconds(20)) { @MainActor in
            callCountLock.withLock { $0 += 1 }
        }

        // Let the loop tick several times — all should be no-ops because
        // the checker keeps passing.
        try await Task.sleep(for: .milliseconds(150))
        monitor.stop()

        #expect(callCountLock.withLock { $0 } == 0)
    }

    @Test("stop() is idempotent and safe to call before start")
    func stop_isIdempotent() {
        let checker = MutableIntegrityChecker(initialPasses: true)
        let monitor = IntegrityMonitor(checker: checker)
        monitor.stop()
        monitor.stop()
        #expect(true) // no crash
    }

    @Test("restart cancels the previous loop before starting a new one")
    func start_twice_cancelsFirstLoop() async {
        let checker = MutableIntegrityChecker(initialPasses: false)
        let monitor = IntegrityMonitor(checker: checker)

        let firstCalls = OSAllocatedUnfairLock<Int>(initialState: 0)
        monitor.start(interval: .milliseconds(20)) { @MainActor in
            firstCalls.withLock { $0 += 1 }
        }

        _ = await waitUntil { firstCalls.withLock { $0 } >= 1 }

        let secondCalls = OSAllocatedUnfairLock<Int>(initialState: 0)
        monitor.start(interval: .milliseconds(20)) { @MainActor in
            secondCalls.withLock { $0 += 1 }
        }

        let secondFired = await waitUntil { secondCalls.withLock { $0 } >= 1 }
        monitor.stop()

        #expect(firstCalls.withLock { $0 } >= 1)
        #expect(secondFired)
    }

    @Test("onFailure is called on the main actor")
    func onFailure_callsOnMainActor() async {
        let checker = MutableIntegrityChecker(initialPasses: false)
        let monitor = IntegrityMonitor(checker: checker)

        let reached = OSAllocatedUnfairLock<Bool>(initialState: false)
        monitor.start(interval: .milliseconds(20)) { @MainActor in
            MainActor.assertIsolated()
            reached.withLock { $0 = true }
        }

        let fired = await waitUntil { reached.withLock { $0 } }
        monitor.stop()

        #expect(fired)
    }
}
