//
//  LaunchAtLoginManager.swift
//  Fullbright
//
//  Manages launch-at-login registration via SMAppService.
//

import Foundation
import ServiceManagement
import os

private let logger = Logger(subsystem: AppIdentifier.serviceID, category: "LaunchAtLogin")

struct LaunchAtLoginManager: LaunchAtLoginManaging {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logger.error("Failed to \(enabled ? "enable" : "disable") launch at login: \(error, privacy: .public)")
            throw error
        }
    }
}
