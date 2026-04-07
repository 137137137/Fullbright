//
//  AuthStateReducer.swift
//  Fullbright
//
//  Pure state-machine for AuthenticationState transitions.
//
//  Extracted from SecureAuthenticationManager so that every transition is
//  exhaustively testable without touching SecureFileStorage, KeychainManager,
//  AuthServerClient, or the integrity checker. All events carry the data the
//  reducer needs — no I/O inside this file.
//

import Foundation

/// Discrete events the authentication state machine responds to.
enum AuthEvent: Sendable, Equatable {
    /// Emitted at app launch after the initial integrity check has run and
    /// both the license and trial managers have been polled.
    case startup(integrityPassed: Bool, licenseState: AuthenticationState?, trialState: AuthenticationState)

    /// Emitted when the background license-validation task sees a
    /// server-returned `.invalid`. The caller supplies the current trial
    /// state so the reducer can fall back to it without re-entering any
    /// side-effecting code.
    case licenseRevokedByServer(trialFallback: AuthenticationState)

    /// Emitted when the background trial-registration task sees a
    /// server-returned `.denied`.
    case trialDeniedByServer

    /// Emitted when the user successfully activates a license in the UI.
    case licenseActivatedLocally(licenseKey: String)

    /// Emitted when the user logs out.
    case loggedOut

    /// Emitted by IntegrityMonitor when a periodic integrity check fails.
    case integrityMonitorFailed
}

/// Pure reducer. Given the current state and an event, produces the next
/// state. Does not perform any I/O.
enum AuthStateReducer {

    static func reduce(
        current: AuthenticationState,
        event: AuthEvent
    ) -> AuthenticationState {
        switch event {

        case let .startup(integrityPassed, licenseState, trialState):
            // Integrity failure overrides everything — a tampered binary
            // can't be trusted to honor any license.
            guard integrityPassed else { return .expired }
            // License has priority over trial when both exist.
            return licenseState ?? trialState

        case let .licenseRevokedByServer(trialFallback):
            // License was revoked server-side. Drop back to whatever the
            // trial state looks like — which may itself be .expired.
            return trialFallback

        case .trialDeniedByServer:
            return .expired

        case let .licenseActivatedLocally(licenseKey):
            return .authenticated(licenseKey: licenseKey)

        case .loggedOut:
            return .expired

        case .integrityMonitorFailed:
            return .expired
        }
    }
}
