//
//  DisplayConfiguring.swift
//  Fullbright
//
//  Abstraction over the SkyLight private-framework display mode setup.
//  Injected into XDRController so the controller stays free of direct
//  dlopen calls and the behavior can be stubbed in tests.
//

import Foundation

@MainActor
protocol DisplayConfiguring {
    /// Applies the SkyLight display-mode configuration that unlocks the
    /// extended EDR headroom needed for XDR brightness. On hardware that
    /// doesn't expose SkyLight, implementations must no-op safely.
    func configureForXDR(displayID: UInt32)
}
