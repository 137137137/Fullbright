//
//  AuthStateObserverTests.swift
//  FullbrightTests
//
//  Uses a lightweight @Observable stub auth manager whose authState we
//  mutate in the test; verifies that AuthStateObserver fires its
//  callback on transitions and ignores unchanged writes.
//

import Foundation
import os
import Testing
@testable import Fullbright

/// Minimal auth manager for observing state. Doesn't implement the full
/// AuthenticationManaging surface — only what AuthStateObserver reads.
@MainActor
@Observable
private final class TestAuthManager: AuthenticationManaging {
    var authState: AuthenticationState = .notAuthenticated
    func start() async {}
    func refreshAuthenticationState() {}
    func startTrial() {}
    func activateLicense(licenseKey: String) async -> (success: Bool, message: String?) { (false, nil) }
    func logout() {}
}

@MainActor
private func waitUntilCount(
    _ count: OSAllocatedUnfairLock<Int>,
    reaches target: Int,
    timeout: Duration = .seconds(2)
) async -> Bool {
    let start = ContinuousClock.now
    while ContinuousClock.now - start < timeout {
        if count.withLock({ $0 }) >= target { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return count.withLock { $0 } >= target
}

@MainActor
@Suite("AuthStateObserver", .serialized)
struct AuthStateObserverTests {

    @Test("onTransition fires when authState changes")
    func transition_firesCallback() async {
        let auth = TestAuthManager()
        let observer = AuthStateObserver(authManager: auth)
        let count = OSAllocatedUnfairLock<Int>(initialState: 0)

        observer.start { @MainActor _ in
            count.withLock { $0 += 1 }
        }

        auth.authState = .expired
        let reached = await waitUntilCount(count, reaches: 1)
        observer.stop()

        #expect(reached)
    }

    @Test("onTransition does not fire when authState is set to the same value")
    func sameValueAssignment_doesNotFire() async throws {
        let auth = TestAuthManager()
        let observer = AuthStateObserver(authManager: auth)
        let count = OSAllocatedUnfairLock<Int>(initialState: 0)

        observer.start { @MainActor _ in
            count.withLock { $0 += 1 }
        }

        // Assign the same value twice. The observation tracking fires each
        // write, but AuthStateObserver dedupes using a lastState snapshot
        // so the callback should see zero transitions.
        auth.authState = .notAuthenticated
        auth.authState = .notAuthenticated
        try await Task.sleep(for: .milliseconds(80))
        observer.stop()

        #expect(count.withLock { $0 } == 0)
    }

    @Test("onTransition fires once per distinct transition")
    func distinctTransitions_fireOnce() async {
        let auth = TestAuthManager()
        let observer = AuthStateObserver(authManager: auth)
        let count = OSAllocatedUnfairLock<Int>(initialState: 0)

        observer.start { @MainActor _ in
            count.withLock { $0 += 1 }
        }

        auth.authState = .expired
        _ = await waitUntilCount(count, reaches: 1)
        auth.authState = .authenticated(licenseKey: "K")
        _ = await waitUntilCount(count, reaches: 2)
        observer.stop()

        #expect(count.withLock { $0 } == 2)
    }

    @Test("stop() prevents further callbacks")
    func stop_preventsFurtherCallbacks() async throws {
        let auth = TestAuthManager()
        let observer = AuthStateObserver(authManager: auth)
        let count = OSAllocatedUnfairLock<Int>(initialState: 0)

        observer.start { @MainActor _ in
            count.withLock { $0 += 1 }
        }

        auth.authState = .expired
        _ = await waitUntilCount(count, reaches: 1)
        observer.stop()

        auth.authState = .authenticated(licenseKey: "K")
        try await Task.sleep(for: .milliseconds(80))

        #expect(count.withLock { $0 } == 1)
    }
}
