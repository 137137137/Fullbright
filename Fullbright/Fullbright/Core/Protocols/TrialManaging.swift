//
//  TrialManaging.swift
//  Fullbright
//

import Foundation

@MainActor
protocol TrialManaging: AnyObject {
    func checkTrialStatus() -> AuthenticationState
    func startTrial() -> AuthenticationState
    func setOnStateChange(_ handler: @escaping @MainActor (AuthenticationState) -> Void)

    #if DEBUG
    func setTrialDaysRemaining(_ days: Int) -> AuthenticationState
    func expireTrial() -> AuthenticationState
    func resetTrial()
    var trialDuration: Int { get }
    func debugTrialInfo() -> String
    #endif
}
