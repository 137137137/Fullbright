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
    private typealias SLSConfigFn = @convention(c) (OpaquePointer, UInt32, UInt32) -> Int32

    private enum SLSMode {
        static let configModes: [UInt32] = [4, 3, 5, 2]
    }

    /// Resolved once on first use (lazily) and cached. `dlopen` already
    /// caches the handle, but the `dlsym` lookup was repeating on every call.
    private static let configureFn: SLSConfigFn? = {
        guard let handle = PrivateFrameworkLoader.loadFramework(skyLightPath) else { return nil }
        return PrivateFrameworkLoader.symbol("SLSConfigureDisplayEnabled", from: handle, as: SLSConfigFn.self)
    }()

    func configureForXDR(displayID: UInt32) {
        guard let slsConfigure = Self.configureFn else { return }

        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let cfg = config else { return }

        for mode in SLSMode.configModes {
            _ = slsConfigure(cfg, mode, 1)
        }

        // `.forSession`, NOT `.permanently`: this reconfigure uses
        // undocumented SkyLight semantics, and on macOS 27 betas the
        // display pipeline has blacked out shortly after launch. A
        // session-scoped configuration guarantees a reboot always returns
        // the display to a known-good state.
        _ = CGCompleteDisplayConfiguration(cfg, .forSession)
    }
}
