//
//  AuthStateObserver.swift
//  Fullbright
//
//  Bridges the authentication manager's `@Observable` `authState` into a
//  transition callback using the first-class `Observations` async sequence
//  (macOS 26+). Extracted from AppCoordinator so the observation mechanic
//  can be tested in isolation.
//

import Foundation
import Observation

@MainActor
protocol AuthStateObserving: AnyObject {
    /// Begins observing `authManager.authState`. The callback fires once per
    /// distinct transition — the initial state does NOT trigger it.
    func start(onTransition: @MainActor @Sendable @escaping (AuthenticationState) -> Void) async
    func stop()
}

@MainActor
final class AuthStateObserver: AuthStateObserving {
    private let authManager: any AuthenticationManaging
    private var task: Task<Void, Never>?

    init(authManager: any AuthenticationManaging) {
        self.authManager = authManager
    }

    nonisolated deinit {
        task?.cancel()
    }

    func start(onTransition: @MainActor @Sendable @escaping (AuthenticationState) -> Void) async {
        let authManager = self.authManager
        // Snapshot the state synchronously so any transition that lands
        // between now and the first `Observations` element is still reported:
        // the snapshot — not the first delivered element — is the baseline.
        let baseline = authManager.authState
        task?.cancel()
        task = Task { @MainActor in
            var lastState = baseline
            for await state in Observations({ authManager.authState }) {
                guard !Task.isCancelled else { return }
                if state != lastState {
                    onTransition(state)
                    lastState = state
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
