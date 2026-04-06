//
//  Bundle+Version.swift
//  Fullbright
//

import Foundation

extension Bundle {
    /// Marketing version string (e.g. "2.3") from Info.plist, or "0.0.0" if unavailable.
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Build number string (e.g. "42") from Info.plist, or nil if unavailable.
    var buildNumber: String? {
        infoDictionary?["CFBundleVersion"] as? String
    }
}
