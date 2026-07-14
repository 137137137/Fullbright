//
//  AuthenticationState+UI.swift
//  Fullbright
//
//  View-layer presentation for AuthenticationState. Kept out of the model
//  file so the domain model stays Foundation-only.
//

import SwiftUI

extension AuthenticationState {
    /// Trial urgency color for status labels.
    var trialColor: Color {
        isTrialUrgent ? .orange : .secondary
    }
}
