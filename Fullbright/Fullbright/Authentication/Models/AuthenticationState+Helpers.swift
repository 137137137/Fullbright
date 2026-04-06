//
//  AuthenticationState+Helpers.swift
//  Fullbright
//

import Foundation

extension AuthenticationState {
    /// Whether the current state permits XDR functionality.
    var canUseXDR: Bool {
        switch self {
        case .authenticated, .trial: return true
        case .expired, .notAuthenticated: return false
        }
    }

    /// Whether the trial is close to expiring (3 days or fewer remaining).
    var isTrialUrgent: Bool {
        guard case .trial(let daysRemaining, _) = self else { return false }
        return daysRemaining <= 3
    }

    /// Whether the user has an active license.
    var isAuthenticated: Bool {
        if case .authenticated = self { return true }
        return false
    }
}
