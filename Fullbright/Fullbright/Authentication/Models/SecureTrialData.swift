//
//  SecureTrialData.swift
//  Fullbright
//
//  Trial data model with integrity checksum.
//

import Foundation

struct SecureTrialData: Codable, Sendable, ChecksumVerifiable {
    let startDate: Date
    let deviceId: String
    let confirmed: Bool // true = server confirmed, false = offline grace
    let checksum: String // Hash of startDate + deviceId + confirmed for integrity

    init(startDate: Date, deviceId: String, confirmed: Bool = false) {
        self.startDate = startDate
        self.deviceId = deviceId
        self.confirmed = confirmed
        self.checksum = Self.computeChecksumValue(startDate: startDate, deviceId: deviceId, confirmed: confirmed)
    }

    func computeChecksum() -> String {
        Self.computeChecksumValue(startDate: startDate, deviceId: deviceId, confirmed: confirmed)
    }

    private static func computeChecksumValue(startDate: Date, deviceId: String, confirmed: Bool) -> String {
        Checksum.sha256("\(startDate.timeIntervalSince1970)-\(deviceId)-\(confirmed)")
    }
}
