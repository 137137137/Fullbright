//
//  SecureLicenseData.swift
//  Fullbright
//
//  License data model with integrity checksum.
//

import Foundation

struct SecureLicenseData: Codable, Sendable, ChecksumVerifiable {
    let licenseKey: String
    let activationDate: Date
    let deviceId: String
    let checksum: String

    init(licenseKey: String, activationDate: Date, deviceId: String) {
        self.licenseKey = licenseKey
        self.activationDate = activationDate
        self.deviceId = deviceId
        self.checksum = Self.computeChecksumValue(licenseKey: licenseKey, activationDate: activationDate, deviceId: deviceId)
    }

    func computeChecksum() -> String {
        Self.computeChecksumValue(licenseKey: licenseKey, activationDate: activationDate, deviceId: deviceId)
    }

    private static func computeChecksumValue(licenseKey: String, activationDate: Date, deviceId: String) -> String {
        Checksum.sha256("\(licenseKey)-\(activationDate.timeIntervalSince1970)-\(deviceId)")
    }
}
