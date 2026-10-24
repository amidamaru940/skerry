import Foundation
import Security
import Darwin

// macOS with an unlocked default login Keychain, from the repository root:
//   swiftc DynamicIsland/managers/LLMUsage/Quota/KeychainReader.swift tests/test_claude_keychain.swift \
//     -o "$TMPDIR/test_claude_keychain" && "$TMPDIR/test_claude_keychain"
// Creates UUID-named disposable items (and removes them); it does not read, refresh,
// or modify any Claude login credential. Not part of the routine runs: it touches the Keychain.
@main
enum ClaudeKeychainTests {
    static func main() throws {
        try requireLoginKeychain()

        let service = "Atoll-keychain-regression-\(UUID().uuidString)"
        let account = "test \"account\" \\ unicode-中文"
        let otherAccount = "other-account"
        defer {
            for name in [account, otherAccount] {
                _ = security(["delete-generic-password", "-s", service, "-a", name])
            }
        }

        for name in [account, otherAccount] {
            try require(security(["add-generic-password", "-s", service, "-a", name, "-w", "fake-seed"]).status == 0,
                    "create disposable credential")
        }
        try require(ClaudeKeychainStore.read(service: service, account: account) == "fake-seed", "initial read")
        let initialPartitions = try partitionIDs(service: service, account: account)
        try require(initialPartitions.contains("apple-tool:"), "initial Apple tool permission")

        // Non-ASCII, so `security -w` prints it as hexadecimal and read() decodes it.
        let secret = #"{"claudeAiOauth":{"accessToken":"FAKE-not-a-token","refreshToken":"FAKE-refresh","expiresAt":42},"mcpOAuth":{"note":"quotes: \" backslash: \\ unicode: 中文"}}"#
        for cycle in 1...3 {
            // Trailing whitespace belongs to the secret and must survive the read.
            let ownerValue = secret + String(repeating: " ", count: cycle)
            try require(security(["add-generic-password", "-U", "-s", service, "-a", account, "-w", ownerValue]).status == 0,
                    "Claude-style owner write \(cycle)")
            try require(ClaudeKeychainStore.read(service: service, account: account) == ownerValue, "exact read \(cycle)")
            try require(try partitionIDs(service: service, account: account) == initialPartitions, "partitions survive read \(cycle)")
        }
        try require(ClaudeKeychainStore.read(service: service, account: otherAccount) == "fake-seed", "other account unchanged")
        try require(ClaudeKeychainStore.read(service: service, account: "missing") == nil, "missing account reads nothing")
        try require(ClaudeKeychainStore.read(service: service, account: nil) == nil, "unscoped read rejected")
        print("PASS: three owner writes read back exactly, unchanged partition permissions, account isolation, missing/unscoped reads")
    }

    /// Refuses unavailable or locked test environments before creating any item.
    private static func requireLoginKeychain() throws {
        var keychain: SecKeychain?
        try require(SecKeychainCopyDefault(&keychain) == errSecSuccess, "default login Keychain required")
        var path = [CChar](repeating: 0, count: Int(PATH_MAX))
        var length = UInt32(path.count)
        try require(SecKeychainGetPath(keychain, &length, &path) == errSecSuccess, "read default Keychain path")
        let name = URL(fileURLWithPath: String(cString: path)).lastPathComponent
        try require(name == "login.keychain-db" || name == "login.keychain", "default Keychain must be login")
        var status: SecKeychainStatus = 0
        let required = UInt32(kSecUnlockStateStatus | kSecReadPermStatus | kSecWritePermStatus)
        try require(SecKeychainGetStatus(keychain, &status) == errSecSuccess && status & required == required,
                    "login Keychain must be unlocked, readable, and writable")
    }

    private static func partitionIDs(service: String, account: String) throws -> Set<String> {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service, kSecAttrAccount as String: account,
                                   kSecReturnRef as String: true]
        var result: CFTypeRef?
        try require(SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, "test item metadata")
        var access: SecAccess?
        try require(SecKeychainItemCopyAccess(result as! SecKeychainItem, &access) == errSecSuccess, "test item ACL")
        let acls = SecAccessCopyMatchingACLList(access!, kSecACLAuthorizationPartitionID) as? [SecACL] ?? []
        var ids = Set<String>()
        for acl in acls {
            var apps: CFArray?, description: CFString?
            var prompt = SecKeychainPromptSelector()
            try require(SecACLCopyContents(acl, &apps, &description, &prompt) == errSecSuccess, "partition contents")
            let hex = description! as String
            var data = Data()
            var index = hex.startIndex
            while index < hex.endIndex {
                let next = hex.index(index, offsetBy: 2)
                data.append(UInt8(hex[index..<next], radix: 16)!)
                index = next
            }
            let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
            ids.formUnion(plist["Partitions"] as? [String] ?? [])
        }
        return ids
    }

    private static func security(_ arguments: [String]) -> (status: Int32, output: Data) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        task.standardInput = FileHandle.nullDevice
        do { try task.run() } catch { return (-1, Data()) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return (task.terminationStatus, data)
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "ClaudeKeychainTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
}
