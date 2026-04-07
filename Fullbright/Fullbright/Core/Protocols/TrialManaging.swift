//
//  TrialManaging.swift
//  Fullbright
//
//  Trial manager protocol — enables injection and testability of
//  the trial start/check/expiry flow.
//

import Foundation

@MainActor
protocol TrialManaging: AnyObject {
    /// Returns the current trial state, deriving days remaining from persisted data.
    func checkTrialStatus() -> AuthenticationState

    /// Starts a fresh trial. Returns the resulting state (`.trial` on success,
    /// `.expired` if a trial was already used or persistence failed).
    func startTrial() -> AuthenticationState

    /// Registers a callback for asynchronous state changes from server responses
    /// (e.g. server denies a previously-unconfirmed trial).
    func setOnStateChange(_ handler: @escaping @MainActor (AuthenticationState) -> Void)

    #if DEBUG
    func setTrialDaysRemaining(_ days: Int) -> AuthenticationState
    func expireTrial() -> AuthenticationState
    func resetTrial()
    var trialDuration: Int { get }
    func debugTrialInfo() -> String
    #endif
}
