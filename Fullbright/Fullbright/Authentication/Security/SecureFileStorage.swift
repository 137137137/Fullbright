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
    private let keychain: any KeychainProviding
    private let deviceIdentifier: any DeviceIdentifying
    private let storageDirectoryOverride: URL?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let saltKeychainKey = StorageKey.encryptionSalt

    /// Legacy hardcoded salt used by pre-2026-04 builds before the keychain
    /// salt existed. Retained ONLY as a migration scaffold so existing users
    /// can upgrade without losing their license/trial state.
    ///
    /// Removal criteria: delete this constant and `migrateFromLegacyKey` once
    /// telemetry shows no active users on a build older than the salt-in-
    /// keychain migration. Until then, the legacy salt is a known-plaintext
    /// value — it provides zero security. Real security comes from the
    /// device-identifier-bound HKDF and AES-GCM authentication.
    private let legacySalt = Data("FuLLbR1gHt$3cur3K3y2024!".utf8)

    /// Random salt stored in keychain. Generated on first run; migrates existing users automatically.
    private let salt: Data

    /// Cached derived key — deterministic given deviceId, serviceID, and salt.
    /// Computed once at init to avoid redundant HKDF on every encrypt/decrypt.
    private let derivedKey: SymmetricKey

    /// Separately-derived HMAC key used by SignedEnvelope. Derived from the
    /// same master material as `derivedKey` but with a distinct HKDF `info`
    /// tag so knowing one key tells you nothing about the other.
    private let signer: any PayloadSigner

    init(keychain: any KeychainProviding,
         deviceIdentifier: any DeviceIdentifying,
         storageDirectory: URL? = nil) {
        self.keychain = keychain
        self.deviceIdentifier = deviceIdentifier
        self.storageDirectoryOverride = storageDirectory

        // Initialize salt. Order of preference:
        //   1. Salt previously persisted to the keychain (normal path).
        //   2. Freshly generated random salt, persisted to the keychain.
        //   3. EMERGENCY — legacy hardcoded salt. This branch only runs if
        //      keychain writes are failing AND no prior salt exists, i.e. a
        //      fresh install on a broken keychain. We fall back to the legacy
        //      salt so the user isn't locked out on relaunch; the downside is
        //      that new data is written with the known-plaintext salt until
        //      keychain recovers, at which point migrateFromLegacyKey will
        //      re-encrypt on the next read.
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
                logger.critical("Keychain salt save failed on fresh init — falling back to legacy salt. This is an EMERGENCY path. Underlying error: \(error, privacy: .public)")
                self.salt = legacySalt
            }
        }

        // Cache the derived key for the primary salt
        self.derivedKey = Self.deriveKey(
            withSalt: self.salt,
            deviceIdentifier: deviceIdentifier
        )
        self.signer = HMACPayloadSigner(
            key: Self.deriveSigningKey(
                withSalt: self.salt,
                deviceIdentifier: deviceIdentifier
            )
        )
    }

    // MARK: - File Storage Paths

    private var storageDirectory: URL {
        if let override = storageDirectoryOverride {
            return override
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask)[0]
        let bundleID = Bundle.main.bundleIdentifier ?? AppIdentifier.serviceID
        return appSupport.appendingPathComponent(bundleID, isDirectory: true)
    }

    private func ensureStorageDirectoryExists() {
        try? FileManager.default.createDirectory(at: storageDirectory,
                                                 withIntermediateDirectories: true)
    }

    private func storageURL(for key: String) -> URL {
        let hashedKey = Checksum.sha256(Data(key.utf8)).prefix(16)
        return storageDirectory.appendingPathComponent(".\(hashedKey)", isDirectory: false)
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
    /// Both re-encryption and the on-disk rewrite are best-effort: if either
    /// fails, the decrypted data is still returned so the user keeps working,
    /// and the next read retries the migration.
    private func migrateFromLegacyKey(encryptedData: Data, url: URL) throws -> Data {
        let legacyKey = Self.deriveKey(withSalt: legacySalt, deviceIdentifier: deviceIdentifier)
        let legacyData = try Self.decryptWithKey(encryptedData, key: legacyKey)
        logger.info("Legacy-salt data detected — attempting migration to current key")

        do {
            let reEncrypted = try encrypt(legacyData)
            try reEncrypted.write(to: url)
            logger.info("Legacy-salt migration succeeded for \(url.lastPathComponent, privacy: .public)")
        } catch {
            // Log the specific cause instead of silently swallowing with try?.
            // Leaving the on-disk file in its legacy state is intentional: the
            // next load will re-enter this code path and retry, so there's no
            // permanent data loss and no infinite loop (decrypt always succeeds
            // against the legacy key).
            logger.error("Legacy-salt migration re-encrypt/write failed: \(error, privacy: .public). Data remains in legacy format and will retry on next load.")
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

    /// Writes a payload by wrapping it in a SignedEnvelope (HMAC-signed)
    /// and then encrypting the envelope bytes with AES-GCM.
    func saveEncrypted<T: Codable>(_ object: T, for key: String) throws {
        let envelopeBytes: Data
        do {
            let envelope = try SignedEnvelope.wrap(object, signer: signer)
            envelopeBytes = try encoder.encode(envelope)
        } catch {
            throw StorageError.encodingFailed(underlying: error)
        }
        ensureStorageDirectoryExists()
        try save(envelopeBytes, for: key)
    }

    /// Loads a payload, preferring v2 SignedEnvelope format. Falls back to
    /// v1 raw-payload format for legacy data (written before the envelope
    /// existed) and transparently re-saves it as v2 on first read so
    /// subsequent loads get the full HMAC protection.
    func loadEncrypted<T: Codable>(_ type: T.Type, for key: String) -> T? {
        guard let data = load(for: key) else { return nil }

        // v2 path — SignedEnvelope
        if let envelope = try? decoder.decode(SignedEnvelope.self, from: data) {
            do {
                return try envelope.unwrap(type, signer: signer)
            } catch {
                logger.error("SignedEnvelope verification failed for key \(key, privacy: .public): \(error, privacy: .public)")
                return nil
            }
        }

        // v1 path — raw payload. AES-GCM already authenticated the bytes at
        // the encryption layer, so a successful decode means the data was
        // not tampered with (under the assumption that the encryption key
        // has not leaked). Re-save as v2 so the next load gets HMAC defense
        // in-depth.
        do {
            let decoded = try decoder.decode(type, from: data)
            logger.info("Migrating legacy v1 payload for key \(key, privacy: .public) → v2 SignedEnvelope")
            try? saveEncrypted(decoded, for: key)
            return decoded
        } catch {
            logger.error("Failed to decode payload at key \(key, privacy: .public): \(error, privacy: .public)")
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

    // MARK: - Legacy v1 Write (test-only)

    #if DEBUG
    /// Writes a raw-payload v1 (pre-SignedEnvelope) record. Used only by
    /// migration tests that need to simulate pre-refactor on-disk data.
    /// Not exposed in Release builds.
    func _writeLegacyV1Payload<T: Encodable>(_ payload: T, for key: String) throws {
        let raw: Data
        do {
            raw = try encoder.encode(payload)
        } catch {
            throw StorageError.encodingFailed(underlying: error)
        }
        try save(raw, for: key)
    }
    #endif

    // MARK: - Key Derivation with HKDF

    private static func deriveKey(withSalt salt: Data, deviceIdentifier: any DeviceIdentifying) -> SymmetricKey {
        deriveSubkey(withSalt: salt, deviceIdentifier: deviceIdentifier, info: "FullbrightEncryption")
    }

    /// HMAC signing key for SignedEnvelope. Uses a distinct `info` string so
    /// knowing the encryption key tells you nothing about the signing key.
    private static func deriveSigningKey(withSalt salt: Data, deviceIdentifier: any DeviceIdentifying) -> SymmetricKey {
        deriveSubkey(withSalt: salt, deviceIdentifier: deviceIdentifier, info: "FullbrightPayloadSignature.v2")
    }

    private static func deriveSubkey(withSalt salt: Data, deviceIdentifier: any DeviceIdentifying, info: String) -> SymmetricKey {
        let deviceId = deviceIdentifier.secureIdentifier
        let keyMaterial = Data("\(deviceId)-\(AppIdentifier.serviceID)".utf8)

        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: keyMaterial),
            salt: salt,
            info: Data(info.utf8),
            outputByteCount: 32
        )
    }
}
