//
//  AuthenticationState.swift
//  Fullbright
//
//  Authentication state model
//

import Foundation

enum AuthenticationState: Equatable, Sendable {
    case notAuthenticated
    case trial(daysRemaining: Int, expiryDate: Date)
    case authenticated(licenseKey: String)
    case expired
}