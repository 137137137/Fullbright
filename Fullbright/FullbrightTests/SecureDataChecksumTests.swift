//
//  SecureDataChecksumTests.swift
//  FullbrightTests
//

import Foundation
import Testing
@testable import Fullbright

struct SecureDataChecksumTests {

    // MARK: - SecureLicenseData

    @Test func licenseData_freshlyConstructed_isValid() {
        let data = SecureLicenseData(
            licenseKey: "ABC-123",
            activationDate: Date(timeIntervalSince1970: 1_700_000_000),
            deviceId: "device-x"
        )
        #expect(data.isValid)
    }

    @Test func licenseData_survivesCodableRoundTrip() throws {
        let original = SecureLicenseData(
            licenseKey: "KEY-1",
            activationDate: Date(timeIntervalSince1970: 1_700_000_000),
            deviceId: "device-y"
        )
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SecureLicenseData.self, from: encoded)
        #expect(decoded.isValid)
        #expect(decoded.licenseKey == original.licenseKey)
        #expect(decoded.deviceId == original.deviceId)
    }

    @Test func licenseData_differentInputs_yieldDifferentChecksums() {
        let a = SecureLicenseData(
            licenseKey: "K1",
            activationDate: Date(timeIntervalSince1970: 1_700_000_000),
            deviceId: "d"
        )
        let b = SecureLicenseData(
            licenseKey: "K2",
            activationDate: Date(timeIntervalSince1970: 1_700_000_000),
            deviceId: "d"
        )
        #expect(a.checksum != b.checksum)
    }

    // MARK: - SecureTrialData

    @Test func trialData_freshlyConstructed_isValid() {
        let data = SecureTrialData(
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            deviceId: "device-x",
            confirmed: false
        )
        #expect(data.isValid)
    }

    @Test func trialData_confirmedFlagAffectsChecksum() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let unconfirmed = SecureTrialData(startDate: date, deviceId: "d", confirmed: false)
        let confirmed = SecureTrialData(startDate: date, deviceId: "d", confirmed: true)
        #expect(unconfirmed.checksum != confirmed.checksum)
    }

    @Test func trialData_survivesCodableRoundTrip() throws {
        let original = SecureTrialData(
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            deviceId: "device-y",
            confirmed: true
        )
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SecureTrialData.self, from: encoded)
        #expect(decoded.isValid)
        #expect(decoded.confirmed == true)
    }
}
