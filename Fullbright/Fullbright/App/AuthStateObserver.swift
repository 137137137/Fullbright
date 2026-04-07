//
//  AuthStateObserver.swift
//  Fullbright
//
//  Wraps the `withObservationTracking` loop that fires when the
//  authentication manager's `authState` changes. Extracted from
//  AppCoordinator so the observation mechanic can be tested in isolation
//  and substituted with a different implementation if @Observable ever
//  exposes a first-class observation API.
//

import Foundation
import os

@MainActor
protocol AuthStateObserving: AnyObject {
    /// Begins observing `authManager.authState`. The callback fires once per
    /// distinct transition — the initial state does NOT trigger it.
    ///
    /// Async so callers (and tests) can guarantee the first observation
    /// registration has completed before they mutate state; otherwise a
    /// write landing before the Task body reaches `withObservationTracking`
    /// would be silently missed.
    func start(onTransition: @MainActor @Sendable @escaping (AuthenticationState) -> Void) async
    func stop()
}

@MainActor
final class AuthStateObserver: AuthStateObserving {
    private let authManager: any AuthenticationManaging
    private let taskLock = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)

    init(authManager: any AuthenticationManaging) {
        self.authManager = authManager
    }

    nonisolated deinit {
        taskLock.withLock { $0?.cancel() }
    }

    func start(onTransition: @MainActor @Sendable @escaping (AuthenticationState) -> Void) async {
        let authManager = self.authManager
        // Handshake: the Task body signals via this continuation as soon as
        // its first `withObservationTracking` registration is installed.
        // `start()` doesn't return until that signal arrives, so any state
        // mutation the caller makes after `start()` is guaranteed to be seen.
        await withCheckedContinuation { (ready: CheckedContinuation<Void, Never>) in
            let task = Task { @MainActor in
                var lastState = authManager.authState
                var didSignalReady = false
                while !Task.isCancelled {
                    await withCheckedContinuation { (changeContinuation: CheckedContinuation<Void, Never>) in
                        withObservationTracking {
                            _ = authManager.authState
                        } onChange: {
                            changeContinuation.resume()
                        }
                        if !didSignalReady {
                            didSignalReady = true
                            ready.resume()
                        }
                    }
                    guard !Task.isCancelled else { return }
                    let newState = authManager.authState
                    if newState != lastState {
                        onTransition(newState)
                        lastState = newState
                    }
                }
            }
            taskLock.withLock { existing in
                existing?.cancel()
                existing = task
            }
        }
    }

    func stop() {
        taskLock.withLock { existing in
            existing?.cancel()
            existing = nil
        }
    }
}
