//
//  TrialManaging.swift
//  Fullbright
//

import Foundation

/// Core trial lifecycle protocol. DEBUG helpers live in the separate
/// `DebugTrialManaging` protocol (see SecureAuthenticationManager+Debug.swift)
/// so production conformers aren't forced to implement test affordances.
@MainActor
protocol TrialManaging: AnyObject {
    func checkTrialStatus() -> AuthenticationState
    func startTrial() -> AuthenticationState
    func setOnStateChange(_ handler: @escaping @MainActor (AuthenticationState) -> Void)
}
