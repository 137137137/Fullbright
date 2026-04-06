//
//  DeviceIdentifier.swift
//  Fullbright
//
//  Device identification via Hardware UUID + Serial Number.
//

import Foundation
import IOKit

struct DeviceIdentifier: DeviceIdentifying, Sendable {
    static let shared = DeviceIdentifier()

    /// Cached identifier for the default service — avoids repeated IOKit lookups.
    private let cachedIdentifier = computeIdentifier(service: AppIdentifier.serviceID)

    /// SHA-256 hash of (Hardware UUID + Serial Number + service), used as a
    /// deterministic, privacy-preserving device fingerprint.
    var secureIdentifier: String {
        cachedIdentifier
    }

    private static func computeIdentifier(service: String) -> String {
        let ioService = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer { IOObjectRelease(ioService) }

        let uuid = platformProperty(kIOPlatformUUIDKey, from: ioService) ?? "unknown-uuid"
        let serial = platformProperty(kIOPlatformSerialNumberKey, from: ioService) ?? "unknown-serial"
        let combined = Data("\(uuid)-\(serial)-\(service)".utf8)
        return Checksum.sha256(combined)
    }

    // MARK: - IOKit

    /// Reads a property from an already-opened IOKit service handle.
    private static func platformProperty(_ key: String, from service: io_service_t) -> String? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
    }
}
