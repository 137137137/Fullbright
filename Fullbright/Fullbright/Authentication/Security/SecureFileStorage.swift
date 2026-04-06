//
//  SecureFileStorage.swift
//  Fullbright
//
//  Secure file-based storage with AES-GCM encryption
//

import Foundation
import CryptoKit
import Security
import os

private let logger = Logger(subsystem: AppIdentifier.serviceID, category: "Storage")

@MainActor
final class SecureFileStorage: SecureStorageProviding {
    static let shared = SecureFileStorage()

    private let keychain: any KeychainProviding
    private let deviceIdentifier: any DeviceIdentifying
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let saltKeychainKey = StorageKey.encryptionSalt
    private let legacySalt = Data("FuLLbR1gHt$3cur3K3y2024!".utf8)

    /// Random salt stored in keychain. Generated on first run; migrates existing users automatically.
    private let salt: Data

    /// Cached derived key — deterministic given deviceId, serviceID, and salt.
    /// Computed once at init to avoid redundant HKDF on every encrypt/decrypt.
    private let derivedKey: SymmetricKey

    init(keychain: any KeychainProviding = KeychainManager.shared,
         deviceIdentifier: any DeviceIdentifying = DeviceIdentifier.shared) {
        self.keychain = keychain
        self.deviceIdentifier = deviceIdentifier

        // Initialize salt
        if let stored = keychain.load(for: saltKeychainKey) {
            self.salt = stored
        } else {
            var random = Data(count: 32)
            let status = random.withUnsafeMutableBytes { ptr -> OSStatus in
                guard let base = ptr.baseAddress else { return errSecAllocate }
                return SecRandomCopyBytes(kSecRandomDefault, 32, base)
            }
            if status != errSecSuccess {
                let fallbackKey = SymmetricKey(size: .bits256)
                random = fallbackKey.withUnsafeBytes { Data($0) }
                logger.warning("SecRandomCopyBytes failed (status=\(status)), using CryptoKit fallback")
            }
            do {
                try keychain.save(random, for: saltKeychainKey)
                self.salt = random
            } catch {
                logger.error("Failed to persist encryption salt to keychain — using legacy salt to avoid data loss on relaunch: \(error, privacy: .public)")
                self.salt = legacySalt
            }
        }

        // Cache the derived key for the primary salt
        self.derivedKey = Self.deriveKey(
            withSalt: self.salt,
            deviceIdentifier: deviceIdentifier
        )
    }

    // MARK: - File Storage Paths

    private func storageURL(for key: String) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask)[0]
        let bundleID = Bundle.main.bundleIdentifier ?? AppIdentifier.serviceID
        let appDir = appSupport.appendingPathComponent(bundleID, isDirectory: true)

        try? FileManager.default.createDirectory(at: appDir,
                                                withIntermediateDirectories: true)

        let hashedKey = Checksum.sha256(Data(key.utf8)).prefix(16)

        return appDir.appendingPathComponent(".\(hashedKey)", isDirectory: false)
    }

    // MARK: - Storage Operations

    private func save(_ data: Data, for key: String) throws {
        let encryptedData = try encrypt(data)
        let url = storageURL(for: key)
        do {
            try encryptedData.write(to: url)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
        } catch {
            throw StorageError.saveFailed(underlying: error)
        }
    }

    private func load(for key: String) -> Data? {
        do {
            let url = storageURL(for: key)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }

            let encryptedData = try Data(contentsOf: url)
            do {
                return try decrypt(encryptedData)
            } catch {
                return try migrateFromLegacyKey(encryptedData: encryptedData, url: url)
            }
        } catch {
            logger.error("Failed to load data: \(error, privacy: .public)")
            return nil
        }
    }

    /// Attempts to decrypt data using the legacy hardcoded salt. On success,
    /// re-encrypts with the current keychain-stored salt for future reads.
    private func migrateFromLegacyKey(encryptedData: Data, url: URL) throws -> Data {
        let legacyKey = Self.deriveKey(withSalt: legacySalt, deviceIdentifier: deviceIdentifier)
        let legacyData = try Self.decryptWithKey(encryptedData, key: legacyKey)
        logger.info("Legacy-encrypted data found — migrating to current key")
        if let reEncrypted = try? encrypt(legacyData) {
            try? reEncrypted.write(to: url)
        } else {
            logger.warning("Legacy migration re-encryption failed — data remains with legacy key")
        }
        return legacyData
    }

    func delete(for key: String) throws {
        let url = storageURL(for: key)
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                throw StorageError.deleteFailed(underlying: error)
            }
        }
    }

    // MARK: - Encrypted Storage

    func saveEncrypted<T: Codable>(_ object: T, for key: String) throws {
        let data: Data
        do {
            data = try encoder.encode(object)
        } catch {
            throw StorageError.encodingFailed(underlying: error)
        }
        try save(data, for: key)
    }

    func loadEncrypted<T: Codable>(_ type: T.Type, for key: String) -> T? {
        guard let data = load(for: key) else { return nil }

        do {
            return try decoder.decode(type, from: data)
        } catch {
            logger.error("Failed to decode object: \(error, privacy: .public)")
            return nil
        }
    }

    // MARK: - Encryption with AES-GCM

    private func encrypt(_ data: Data) throws -> Data {
        do {
            let sealedBox = try AES.GCM.seal(data, using: derivedKey)
            guard let combined = sealedBox.combined else {
                throw EncryptionError.encryptionFailed(underlying: NSError(domain: "Fullbright", code: -1, userInfo: [NSLocalizedDescriptionKey: "SealedBox.combined returned nil"]))
            }
            return combined
        } catch let error as EncryptionError {
            throw error
        } catch {
            throw EncryptionError.encryptionFailed(underlying: error)
        }
    }

    private func decrypt(_ data: Data) throws -> Data {
        try Self.decryptWithKey(data, key: derivedKey)
    }

    private static func decryptWithKey(_ data: Data, key: SymmetricKey) throws -> Data {
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            return try AES.GCM.open(sealedBox, using: key)
        } catch let error as EncryptionError {
            throw error
        } catch {
            throw EncryptionError.decryptionFailed(underlying: error)
        }
    }

    // MARK: - Key Derivation with HKDF

    private static func deriveKey(withSalt salt: Data, deviceIdentifier: any DeviceIdentifying) -> SymmetricKey {
        let deviceId = deviceIdentifier.secureIdentifier
        let keyMaterial = Data("\(deviceId)-\(AppIdentifier.serviceID)".utf8)

        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: keyMaterial),
            salt: salt,
            info: Data("FullbrightEncryption".utf8),
            outputByteCount: 32
        )
    }
}
