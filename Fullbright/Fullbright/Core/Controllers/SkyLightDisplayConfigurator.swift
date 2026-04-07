//
//  SkyLightDisplayConfigurator.swift
//  Fullbright
//
//  Private SkyLight.framework display-mode wrangling, lifted out of
//  XDRController so the unsafe `dlopen` + `CGBeginDisplayConfiguration`
//  code lives in one clearly-labeled place and can be stubbed in tests.
//
//  Historical note: the sequence of SLSConfigureDisplayEnabled modes
//  (4, 3, 5, 2) was reverse-engineered from macOS's own HDR brightness
//  behavior. The exact semantics of each mode are undocumented; the
//  sequence is what reliably unlocks the XDR EDR headroom across every
//  tested display generation.
//

import Foundation
import CoreGraphics

private let skyLightPath = "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight"

@MainActor
struct SkyLightDisplayConfigurator: DisplayConfiguring {
    private enum SLSMode {
        static let configModes: [UInt32] = [4, 3, 5, 2]
    }

    func configureForXDR(displayID: UInt32) {
        typealias SLSConfigFn = @convention(c) (OpaquePointer, UInt32, UInt32) -> Int32

        guard let slHandle = PrivateFrameworkLoader.loadFramework(skyLightPath),
              let slsConfigure: SLSConfigFn = PrivateFrameworkLoader.symbol(
                  "SLSConfigureDisplayEnabled", from: slHandle, as: SLSConfigFn.self
              ) else { return }

        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let cfg = config else { return }

        for mode in SLSMode.configModes {
            _ = slsConfigure(cfg, mode, 1)
        }

        _ = CGCompleteDisplayConfiguration(cfg, .permanently)
    }
}
