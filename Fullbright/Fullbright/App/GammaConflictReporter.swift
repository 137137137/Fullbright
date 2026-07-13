//
//  GammaConflictReporter.swift
//  Fullbright
//
//  When XDR is force-disabled because gamma writes stop sticking, tell
//  the user *why* instead of silently turning off — and name the likely
//  culprit. App list mirrors the gamma-touching apps BrightIntosh ships
//  as "incompatible apps".
//

import AppKit

@MainActor
enum GammaConflictReporter {
    /// Apps known to write display gamma tables and fight over them.
    private static let knownGammaApps: [(name: String, bundleIDs: [String])] = [
        ("f.lux", ["org.herf.Flux"]),
        ("Lunar", ["fyi.lunar.Lunar"]),
        ("BetterDisplay", ["pro.betterdisplay.BetterDisplay", "com.github.wulkano.BetterDisplay"]),
        ("MonitorControl", ["me.guillaumeb.MonitorControl", "app.monitorcontrol.MonitorControl", "app.monitorcontrol.MonitorControlLite"]),
        ("Vivid", ["com.getvivid.vivid", "com.getvivid.Vivid"]),
        ("DisplayBuddy", ["com.sids.DisplayBuddy", "com.sids.displaybuddy-setapp"]),
        ("Gamma Control", ["ca.michelf.gamma-control"]),
        ("QuickShade", ["jp.questbeat.Shade"]),
        ("Iris", ["com.iristech.Iris", "com.iristech.IrisMini"]),
    ]

    static func runningGammaApps() -> [String] {
        let runningIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return knownGammaApps
            .filter { app in app.bundleIDs.contains { runningIDs.contains($0) } }
            .map(\.name)
    }

    static func showConflictAlert() {
        let offenders = runningGammaApps()

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "XDR Mode Turned Off"
        if offenders.isEmpty {
            alert.informativeText = "Another process kept overwriting Fullbright's display adjustments, or macOS is ignoring gamma changes (this has happened on beta releases). Quit other display-utility apps and try turning XDR back on."
        } else {
            let names = offenders.joined(separator: ", ")
            alert.informativeText = "\(names) kept overwriting Fullbright's display adjustments. Quit \(offenders.count == 1 ? "it" : "them") and turn XDR back on."
        }
        alert.addButton(withTitle: "OK")

        NSApp.activate()
        alert.runModal()
    }
}
