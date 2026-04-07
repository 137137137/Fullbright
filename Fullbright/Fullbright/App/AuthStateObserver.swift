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
    /// distinct transition — the initial state does NOT trigger it. Calling
    /// `start` while already observing is a no-op and logs a warning.
    func start(onTransition: @MainActor @Sendable @escaping (AuthenticationState) -> Void)
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

    func start(onTransition: @MainActor @Sendable @escaping (AuthenticationState) -> Void) {
        let authManager = self.authManager
        let task = Task { @MainActor in
            var lastState = authManager.authState
            while !Task.isCancelled {
                await withCheckedContinuation { continuation in
                    withObservationTracking {
                        _ = authManager.authState
                    } onChange: {
                        continuation.resume()
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

    func stop() {
        taskLock.withLock { existing in
            existing?.cancel()
            existing = nil
        }
    }
}
