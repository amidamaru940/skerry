/*
 * Skerry — a fork of Atoll (DynamicIsland)
 * Copyright (C) 2026 amidamaru940 and Skerry contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import Foundation
import LocalAuthentication
import os
import Security

/// A provider whose API key the Screen Assistant keeps. The raw value is the
/// Keychain account.
enum ScreenAssistantKeyAccount: String, CaseIterable {
    case gemini
    case openai
    case claude
    case groq

    /// The UserDefaults name upstream kept this key under, in plain text.
    /// Only the migration reads it; nothing writes it any more.
    var legacyDefaultsName: String {
        switch self {
        case .gemini: return "geminiApiKey"
        case .openai: return "openaiApiKey"
        case .claude: return "claudeApiKey"
        case .groq: return "groqApiKey"
        }
    }

    /// The account for a provider; nil for the local model, which has no key.
    init?(provider: AIModelProvider) {
        switch provider {
        case .gemini: self = .gemini
        case .openai: self = .openai
        case .claude: self = .claude
        case .groq: self = .groq
        case .local: return nil
        }
    }
}

/// A Keychain call that did not succeed. It carries the status alone, never
/// the key.
struct ScreenAssistantKeyStoreError: Error, Equatable {
    let status: OSStatus
}

/// What the interface says about a provider's key.
enum ScreenAssistantKeyState: Equatable {
    case saved
    case notSet
    /// The Keychain answered with an error: a key may be there, out of reach.
    case unavailable
}

/// Where the Screen Assistant's API keys live. The app uses the Keychain;
/// tests use a store in memory.
protocol ScreenAssistantKeyStore {
    /// The stored key, or nil when none is stored.
    func read(_ account: ScreenAssistantKeyAccount) throws -> String?
    /// Whether a key is stored, from its attributes alone: the secret is not
    /// decrypted.
    func contains(_ account: ScreenAssistantKeyAccount) throws -> Bool
    func write(_ value: String, for account: ScreenAssistantKeyAccount) throws
    /// Deleting a key that is not stored succeeds.
    func delete(_ account: ScreenAssistantKeyAccount) throws
}

/// Generic passwords in the login Keychain. The data protection Keychain is
/// not used: it needs a provisioning profile, which Skerry does not have
/// (errSecMissingEntitlement, -34018). Each build keeps its own items: the
/// service is the bundle identifier, so Skerry Dev never reads Skerry's keys.
struct KeychainScreenAssistantKeyStore: ScreenAssistantKeyStore {
    let service: String

    init(bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "io.github.amidamaru940.skerry") {
        service = bundleIdentifier + ".screen-assistant"
    }

    /// Every call carries a context that may not ask: one that would need a
    /// password or Touch ID fails with a status instead of showing a window.
    private func query(for account: ScreenAssistantKeyAccount) -> [String: Any] {
        let context = LAContext()
        context.interactionNotAllowed = true
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
            kSecAttrSynchronizable as String: false,
            kSecUseAuthenticationContext as String: context,
        ]
    }

    func read(_ account: ScreenAssistantKeyAccount) throws -> String? {
        var query = query(for: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw ScreenAssistantKeyStoreError(status: status) }
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            throw ScreenAssistantKeyStoreError(status: errSecDecode)
        }
        return value
    }

    func contains(_ account: ScreenAssistantKeyAccount) throws -> Bool {
        var query = query(for: account)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else { throw ScreenAssistantKeyStoreError(status: status) }
        return true
    }

    func write(_ value: String, for account: ScreenAssistantKeyAccount) throws {
        let data = Data(value.utf8)
        let status = SecItemUpdate(query(for: account) as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw ScreenAssistantKeyStoreError(status: status) }

        var attributes = query(for: account)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw ScreenAssistantKeyStoreError(status: addStatus) }
    }

    func delete(_ account: ScreenAssistantKeyAccount) throws {
        let status = SecItemDelete(query(for: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ScreenAssistantKeyStoreError(status: status)
        }
    }
}

/// Moves the keys upstream kept in UserDefaults, in plain text, into the
/// store. A plain copy is removed only once the store hands back exactly what
/// was written; otherwise it stays, and the next launch tries again.
enum ScreenAssistantKeyMigration {
    /// Set once every key has left UserDefaults.
    static let markerName = "didMigrateScreenAssistantKeys"

    private static let log = os.Logger(subsystem: Bundle.main.bundleIdentifier ?? "Skerry", category: "ScreenAssistantKeys")

    /// Returns how many keys moved at this run.
    @discardableResult
    static func run(defaults: UserDefaults, store: ScreenAssistantKeyStore) -> Int {
        guard !defaults.bool(forKey: markerName) else { return 0 }
        var moved = 0
        var everyKeyDone = true
        for account in ScreenAssistantKeyAccount.allCases {
            let name = account.legacyDefaultsName
            guard let plain = defaults.string(forKey: name) else {
                // Something that is not a string: no key to move, only litter.
                if defaults.object(forKey: name) != nil {
                    defaults.removeObject(forKey: name)
                }
                continue
            }
            if plain.isEmpty {
                defaults.removeObject(forKey: name)
                continue
            }
            do {
                try store.write(plain, for: account)
                guard try store.read(account) == plain else {
                    everyKeyDone = false
                    log.error("Screen Assistant key \(account.rawValue, privacy: .public) kept in place: the Keychain read back something else")
                    continue
                }
                defaults.removeObject(forKey: name)
                moved += 1
            } catch let error as ScreenAssistantKeyStoreError {
                everyKeyDone = false
                log.error("Screen Assistant key \(account.rawValue, privacy: .public) kept in place: OSStatus \(error.status, privacy: .public)")
            } catch {
                everyKeyDone = false
                log.error("Screen Assistant key \(account.rawValue, privacy: .public) kept in place")
            }
        }
        if everyKeyDone {
            defaults.set(true, forKey: markerName)
        }
        return moved
    }
}

/// What the app does with the keys, on a given store and defaults. The app
/// runs it on ScreenAssistantKeys' queue; tests run it on a store in memory.
struct ScreenAssistantKeyService {
    let store: ScreenAssistantKeyStore
    let defaults: UserDefaults

    private static let log = os.Logger(subsystem: Bundle.main.bundleIdentifier ?? "Skerry", category: "ScreenAssistantKeys")

    /// The saved key, or nil when there is none or the Keychain would not
    /// hand it over without asking.
    func key(for account: ScreenAssistantKeyAccount) -> String? {
        do {
            guard let value = try store.read(account), !value.isEmpty else { return nil }
            return value
        } catch let error as ScreenAssistantKeyStoreError {
            Self.log.error("Screen Assistant key \(account.rawValue, privacy: .public) not read: OSStatus \(error.status, privacy: .public)")
            return nil
        } catch {
            return nil
        }
    }

    /// Saved, not set, or out of reach; the secret itself is never read.
    func state(of account: ScreenAssistantKeyAccount) -> ScreenAssistantKeyState {
        do {
            return try store.contains(account) ? .saved : .notSet
        } catch let error as ScreenAssistantKeyStoreError {
            Self.log.error("Screen Assistant key \(account.rawValue, privacy: .public) not checked: OSStatus \(error.status, privacy: .public)")
            return .unavailable
        } catch {
            return .unavailable
        }
    }

    /// Saves a key typed by the person. A plain copy the migration could not
    /// move yet goes too, so a later launch never puts the old key back; when
    /// the write fails, that copy stays for the migration to try again.
    func save(_ value: String, for account: ScreenAssistantKeyAccount) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        do {
            try store.write(trimmed, for: account)
            defaults.removeObject(forKey: account.legacyDefaultsName)
            return true
        } catch let error as ScreenAssistantKeyStoreError {
            Self.log.error("Screen Assistant key \(account.rawValue, privacy: .public) not saved: OSStatus \(error.status, privacy: .public)")
            return false
        } catch {
            return false
        }
    }

    /// «Delete key»: the Keychain item and any plain copy left behind.
    func delete(_ account: ScreenAssistantKeyAccount) -> Bool {
        do {
            try store.delete(account)
            defaults.removeObject(forKey: account.legacyDefaultsName)
            return true
        } catch let error as ScreenAssistantKeyStoreError {
            Self.log.error("Screen Assistant key \(account.rawValue, privacy: .public) not deleted: OSStatus \(error.status, privacy: .public)")
            return false
        } catch {
            return false
        }
    }
}

/// The Screen Assistant's keys as the app reads and writes them. Every call
/// runs on one serial queue, so a read made while the launch migration still
/// runs waits for it and never misses a key that is on its way.
enum ScreenAssistantKeys {
    private static let queue = DispatchQueue(label: "Skerry.ScreenAssistantKeys", qos: .userInitiated)
    private static let service = ScreenAssistantKeyService(store: KeychainScreenAssistantKeyStore(), defaults: .standard)
    private static let log = os.Logger(subsystem: Bundle.main.bundleIdentifier ?? "Skerry", category: "ScreenAssistantKeys")

    /// At launch, off the main thread, before the assistant first reads a key.
    static func migrateAtLaunch() {
        queue.async {
            let moved = ScreenAssistantKeyMigration.run(defaults: service.defaults, store: service.store)
            if moved > 0 {
                // The count only, never a key.
                log.notice("Screen Assistant keys moved to the Keychain: \(moved, privacy: .public)")
            }
        }
    }

    static func key(for account: ScreenAssistantKeyAccount) -> String? {
        queue.sync { service.key(for: account) }
    }

    static func key(forProvider provider: AIModelProvider) -> String? {
        ScreenAssistantKeyAccount(provider: provider).flatMap { key(for: $0) }
    }

    /// Each key's state, handed to the main thread. The check waits for the
    /// launch migration on the queue, never on the main thread.
    static func states(of accounts: [ScreenAssistantKeyAccount] = ScreenAssistantKeyAccount.allCases,
                       completion: @escaping ([ScreenAssistantKeyAccount: ScreenAssistantKeyState]) -> Void) {
        queue.async {
            var states: [ScreenAssistantKeyAccount: ScreenAssistantKeyState] = [:]
            for account in accounts {
                states[account] = service.state(of: account)
            }
            DispatchQueue.main.async { completion(states) }
        }
    }

    /// False when the Keychain refused the key: the interface keeps what was
    /// typed and says so.
    @discardableResult
    static func save(_ value: String, for account: ScreenAssistantKeyAccount) -> Bool {
        queue.sync { service.save(value, for: account) }
    }

    @discardableResult
    static func delete(_ account: ScreenAssistantKeyAccount) -> Bool {
        queue.sync { service.delete(account) }
    }
}
