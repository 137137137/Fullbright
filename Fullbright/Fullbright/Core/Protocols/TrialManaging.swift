//
//  TrialManaging.swift
//  Fullbright
//

import Foundation

/// Events published by a TrialManaging conformer. Currently there is one:
/// `deniedByServer`, emitted when trial registration is explicitly denied.
enum TrialEvent: Sendable, Equatable {
    case deniedByServer
}

/// Core trial lifecycle protocol. DEBUG helpers live in the separate
/// `DebugTrialManaging` protocol (see SecureAuthenticationManager+Debug.swift)
/// so production conformers aren't forced to implement test affordances.
///
/// Single-subscriber `events` stream — see LicenseManaging for rationale.
@MainActor
protocol TrialManaging: AnyObject {
    func checkTrialStatus() -> AuthenticationState
    func startTrial() -> AuthenticationState
    var events: AsyncStream<TrialEvent> { get }
}
