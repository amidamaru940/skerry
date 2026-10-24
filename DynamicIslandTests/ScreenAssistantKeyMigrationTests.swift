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

import Security
import XCTest
@testable import Atoll

/// R2c: the Screen Assistant's API keys leave UserDefaults for the Keychain.
/// Everything here runs on a store in memory and a throwaway defaults suite;
/// the real Keychain and the app's own defaults are never touched.
final class ScreenAssistantKeyMigrationTests: XCTestCase {

    /// A store in memory that can be made to fail, or to hand back something
    /// other than what was written. It notes what UserDefaults held at each
    /// write and read, to show the plain copy is still there at that point.
    private final class MemoryKeyStore: ScreenAssistantKeyStore {
        var items: [ScreenAssistantKeyAccount: String] = [:]
        var failingWrites: Set<ScreenAssistantKeyAccount> = []
        var failingReads: Set<ScreenAssistantKeyAccount> = []
        var failingContains: Set<ScreenAssistantKeyAccount> = []
        var readBack: [ScreenAssistantKeyAccount: String] = [:]
        var plainCopyAtWrite: [ScreenAssistantKeyAccount: String?] = [:]
        var plainCopyAtRead: [ScreenAssistantKeyAccount: String?] = [:]
        private(set) var writeCount = 0
        private(set) var readCount = 0
        weak var defaults: UserDefaults?

        func read(_ account: ScreenAssistantKeyAccount) throws -> String? {
            readCount += 1
            plainCopyAtRead[account] = defaults?.string(forKey: account.legacyDefaultsName)
            if failingReads.contains(account) {
                throw ScreenAssistantKeyStoreError(status: errSecInteractionNotAllowed)
            }
            return readBack[account] ?? items[account]
        }

        func contains(_ account: ScreenAssistantKeyAccount) throws -> Bool {
            if failingContains.contains(account) {
                throw ScreenAssistantKeyStoreError(status: errSecInteractionNotAllowed)
            }
            return items[account] != nil
        }

        func write(_ value: String, for account: ScreenAssistantKeyAccount) throws {
            writeCount += 1
            plainCopyAtWrite[account] = defaults?.string(forKey: account.legacyDefaultsName)
            if failingWrites.contains(account) {
                throw ScreenAssistantKeyStoreError(status: errSecInteractionNotAllowed)
            }
            items[account] = value
        }

        func delete(_ account: ScreenAssistantKeyAccount) throws {
            items[account] = nil
        }
    }

    private static let fakeKeys: [ScreenAssistantKeyAccount: String] = [
        .gemini: "FAKE-gemini-0001",
        .openai: "FAKE-openai-0002",
        .claude: "FAKE-claude-0003",
        .groq: "FAKE-groq-0004",
    ]

    private var suiteName = ""
    private var defaults: UserDefaults!
    private var store: MemoryKeyStore!

    override func setUp() {
        super.setUp()
        suiteName = "ScreenAssistantKeyMigrationTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = MemoryKeyStore()
        store.defaults = defaults
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        store = nil
        super.tearDown()
    }

    private func storePlainKeys(_ keys: [ScreenAssistantKeyAccount: String] = fakeKeys) {
        for (account, value) in keys {
            defaults.set(value, forKey: account.legacyDefaultsName)
        }
    }

    private func plain(_ account: ScreenAssistantKeyAccount) -> String? {
        defaults.string(forKey: account.legacyDefaultsName)
    }

    private var marked: Bool {
        defaults.bool(forKey: ScreenAssistantKeyMigration.markerName)
    }

    func testTheLegacyNamesAreUpstreamsDefaultsKeys() {
        XCTAssertEqual(ScreenAssistantKeyAccount.allCases.map(\.legacyDefaultsName),
                       ["geminiApiKey", "openaiApiKey", "claudeApiKey", "groqApiKey"])
        XCTAssertEqual(ScreenAssistantKeyAccount.allCases.map(\.rawValue), ["gemini", "openai", "claude", "groq"])
        XCTAssertNil(ScreenAssistantKeyAccount(provider: .local), "the local model has no key")
        XCTAssertEqual(ScreenAssistantKeyAccount(provider: .groq), .groq)
    }

    func testEachBuildKeepsItsOwnKeychainService() {
        XCTAssertEqual(KeychainScreenAssistantKeyStore(bundleIdentifier: "io.github.amidamaru940.skerry.dev").service,
                       "io.github.amidamaru940.skerry.dev.screen-assistant")
        XCTAssertEqual(KeychainScreenAssistantKeyStore(bundleIdentifier: "io.github.amidamaru940.skerry").service,
                       "io.github.amidamaru940.skerry.screen-assistant")
    }

    func testAllFourKeysMove() {
        storePlainKeys()

        let moved = ScreenAssistantKeyMigration.run(defaults: defaults, store: store)

        XCTAssertEqual(moved, 4)
        XCTAssertEqual(store.items, Self.fakeKeys)
        for account in ScreenAssistantKeyAccount.allCases {
            XCTAssertNil(plain(account), "\(account.legacyDefaultsName) left in UserDefaults")
        }
        XCTAssertTrue(marked)
    }

    func testThePlainCopyGoesOnlyAfterTheWriteAndTheReadBack() {
        storePlainKeys()
        store.readBack[.claude] = "FAKE-something-else"
        store.failingReads = [.groq]

        let moved = ScreenAssistantKeyMigration.run(defaults: defaults, store: store)

        XCTAssertEqual(moved, 2)
        for account in ScreenAssistantKeyAccount.allCases {
            XCTAssertEqual(store.plainCopyAtWrite[account], Self.fakeKeys[account], "\(account): copy gone before the write")
            XCTAssertEqual(store.plainCopyAtRead[account], Self.fakeKeys[account], "\(account): copy gone before the read")
        }
        XCTAssertNil(plain(.gemini))
        XCTAssertNil(plain(.openai))
        XCTAssertEqual(plain(.claude), Self.fakeKeys[.claude], "removed though the read back differed")
        XCTAssertEqual(plain(.groq), Self.fakeKeys[.groq], "removed though the read back failed")
        XCTAssertFalse(marked, "marked done with two keys still in UserDefaults")
    }

    func testAFailedWriteKeepsThePlainCopyAndTheNextLaunchTriesAgain() {
        storePlainKeys()
        store.failingWrites = [.openai]

        XCTAssertEqual(ScreenAssistantKeyMigration.run(defaults: defaults, store: store), 3)

        XCTAssertEqual(plain(.openai), Self.fakeKeys[.openai])
        XCTAssertNil(store.items[.openai])
        XCTAssertNil(plain(.gemini))
        XCTAssertFalse(marked)

        store.failingWrites = []
        XCTAssertEqual(ScreenAssistantKeyMigration.run(defaults: defaults, store: store), 1)

        XCTAssertNil(plain(.openai))
        XCTAssertEqual(store.items, Self.fakeKeys)
        XCTAssertTrue(marked)
    }

    func testEmptyStringsAreRemovedWithoutAWrite() {
        storePlainKeys([.gemini: "", .openai: "", .claude: "FAKE-claude-0003"])

        XCTAssertEqual(ScreenAssistantKeyMigration.run(defaults: defaults, store: store), 1)

        XCTAssertNil(defaults.object(forKey: "geminiApiKey"))
        XCTAssertNil(defaults.object(forKey: "openaiApiKey"))
        XCTAssertNil(defaults.object(forKey: "claudeApiKey"))
        XCTAssertEqual(store.writeCount, 1, "an empty key was written to the store")
        XCTAssertEqual(store.items, [.claude: "FAKE-claude-0003"])
        XCTAssertTrue(marked)
    }

    func testNothingStoredMarksDoneAndWritesNothing() {
        XCTAssertEqual(ScreenAssistantKeyMigration.run(defaults: defaults, store: store), 0)

        XCTAssertEqual(store.writeCount, 0)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(marked)
    }

    func testASecondRunChangesNothing() {
        storePlainKeys()
        ScreenAssistantKeyMigration.run(defaults: defaults, store: store)
        let items = store.items
        let writes = store.writeCount
        let stored = defaults.persistentDomain(forName: suiteName) as NSDictionary?

        XCTAssertEqual(ScreenAssistantKeyMigration.run(defaults: defaults, store: store), 0)

        XCTAssertEqual(store.items, items)
        XCTAssertEqual(store.writeCount, writes)
        XCTAssertEqual(defaults.persistentDomain(forName: suiteName) as NSDictionary?, stored)
    }

    func testANonStringLegacyValueIsRemoved() {
        defaults.set(Data([0x01, 0x02]), forKey: "geminiApiKey")
        defaults.set(["FAKE-not-a-key"], forKey: "groqApiKey")
        storePlainKeys([.claude: "FAKE-claude-0003"])

        XCTAssertEqual(ScreenAssistantKeyMigration.run(defaults: defaults, store: store), 1)

        XCTAssertNil(defaults.object(forKey: "geminiApiKey"), "a value that is not a string stayed behind")
        XCTAssertNil(defaults.object(forKey: "groqApiKey"), "a value that is not a string stayed behind")
        XCTAssertEqual(store.items, [.claude: "FAKE-claude-0003"], "only the string key goes to the store")
        XCTAssertTrue(marked)
    }

    // MARK: - What the interface calls

    private var service: ScreenAssistantKeyService {
        ScreenAssistantKeyService(store: store, defaults: defaults)
    }

    func testSavingRemovesALingeringPlainCopyAfterTheWrite() {
        storePlainKeys([.gemini: "FAKE-gemini-old"])

        XCTAssertTrue(service.save("  FAKE-gemini-new\n", for: .gemini))

        XCTAssertEqual(store.items[.gemini], "FAKE-gemini-new", "the typed key is trimmed")
        XCTAssertEqual(store.plainCopyAtWrite[.gemini], "FAKE-gemini-old", "copy gone before the write")
        XCTAssertNil(defaults.object(forKey: "geminiApiKey"), "the old plain copy would come back at the next launch")
    }

    func testAFailedSaveSaysSoAndKeepsThePlainCopy() {
        storePlainKeys([.openai: "FAKE-openai-old"])
        store.failingWrites = [.openai]

        XCTAssertFalse(service.save("FAKE-openai-new", for: .openai))

        XCTAssertNil(store.items[.openai])
        XCTAssertEqual(plain(.openai), "FAKE-openai-old", "the migration has nothing left to try again with")

        XCTAssertFalse(service.save("   ", for: .claude), "an empty key counts as saved")
        XCTAssertEqual(store.writeCount, 1, "an empty key was written")
    }

    func testTheStateTellsAnErrorFromNoKeyWithoutReadingTheSecret() {
        store.items[.gemini] = "FAKE-gemini-0001"
        store.failingContains = [.openai]

        XCTAssertEqual(service.state(of: .gemini), .saved)
        XCTAssertEqual(service.state(of: .claude), .notSet)
        XCTAssertEqual(service.state(of: .openai), .unavailable, "an error shown as «Not Set»")
        XCTAssertEqual(store.readCount, 0, "the state decrypted the secret")
    }
}
