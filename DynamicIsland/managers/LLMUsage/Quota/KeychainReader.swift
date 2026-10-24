import Foundation
import Security

enum KeychainReader {
    static func genericPassword(service: String, account: String? = nil) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if let account { query[kSecAttrAccount as String] = account } // only filter by account when given
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // Read the secret of the most-recently-modified generic password whose service starts
    // with `servicePrefix`. Claude Code namespaces its credential item by a per-install hash
    // ("Claude Code-credentials-<hash>") and rotates it, leaving the un-suffixed item stale;
    // following the freshest item keeps quota working across that migration without hardcoding
    // a hash. The enumeration requests attributes only (no kSecReturnData), so decrypting — and
    // the Keychain access prompt it triggers — happens exactly once, for the chosen item.
    static func freshestGenericPassword(
        servicePrefix: String,
        readSecret: (String, String?) -> String? = genericPassword
    ) -> (service: String, account: String?, secret: String)? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return nil }

        let freshest = items
            .compactMap { attrs -> (service: String, account: String?, modified: Date)? in
                guard let service = attrs[kSecAttrService as String] as? String,
                      service.hasPrefix(servicePrefix),
                      let modified = attrs[kSecAttrModificationDate as String] as? Date
                else { return nil }
                return (service, attrs[kSecAttrAccount as String] as? String, modified)
            }
            .max { $0.modified < $1.modified }

        guard let freshest, let secret = readSecret(freshest.service, freshest.account) else { return nil }
        return (freshest.service, freshest.account, secret)
    }

}

/// Claude Code keeps its login in the Keychain through Apple's `security` tool; read it
/// through the same tool. Read-only: the item is Claude Code's, and there is no write
/// path here. Updating a file-based Keychain secret resets its partition ACL to the
/// writer's identity, so any write from Skerry would make Claude Code ask for access
/// again at its next read.
enum ClaudeKeychainStore {
    static func read(service: String, account: String?) -> String? {
        guard let account else { return nil }
        let result = run(arguments: ["find-generic-password", "-s", service, "-a", account, "-w"])
        guard result.status == 0, var secret = String(data: result.output, encoding: .utf8) else { return nil }
        // security appends a newline; do not trim whitespace belonging to the secret.
        if secret.hasSuffix("\n") { secret.removeLast() }
        // For non-ASCII/control bytes, `security -w` prints hexadecimal instead
        // of the original bytes. Claude's payload is a JSON object in either case.
        if secret.utf8.count.isMultiple(of: 2), secret.utf8.allSatisfy({
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }) {
            let bytes = Array(secret.utf8)
            var decoded = Data()
            for index in stride(from: 0, to: bytes.count, by: 2) {
                guard let byte = UInt8(String(decoding: bytes[index...index + 1], as: UTF8.self), radix: 16) else { return nil }
                decoded.append(byte)
            }
            if let json = String(data: decoded, encoding: .utf8),
               json.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") { return json }
        }
        return secret
    }

    private static func run(arguments: [String]) -> (status: Int32, output: Data) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        // Errors can name the item. Never log them.
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return (-1, Data()) }
        let timeout = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 15, execute: timeout)
        defer { timeout.cancel() }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, data)
    }
}
