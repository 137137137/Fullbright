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
    /// Highest wall-clock time ever observed while this trial was checked.
    /// Rolling the system clock backward past this watermark expires the
    /// trial instead of extending it. Optional so records written by older
    /// builds still decode (nil = watermark starts at startDate).
    ///
    /// Deliberately NOT part of `checksum` — old records' checksums must
    /// keep verifying. Whole-payload integrity comes from the SignedEnvelope
    /// HMAC at the storage layer.
    let latestObservedDate: Date?

    init(startDate: Date, deviceId: String, confirmed: Bool = false, latestObservedDate: Date? = nil) {
        self.startDate = startDate
        self.deviceId = deviceId
        self.confirmed = confirmed
        self.latestObservedDate = latestObservedDate
        self.checksum = Self.computeChecksumValue(startDate: startDate, deviceId: deviceId, confirmed: confirmed)
    }

    func computeChecksum() -> String {
        Self.computeChecksumValue(startDate: startDate, deviceId: deviceId, confirmed: confirmed)
    }

    private static func computeChecksumValue(startDate: Date, deviceId: String, confirmed: Bool) -> String {
        Checksum.sha256("\(startDate.timeIntervalSince1970)-\(deviceId)-\(confirmed)")
    }
}
