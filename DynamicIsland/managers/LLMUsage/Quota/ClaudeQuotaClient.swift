import Foundation

actor ClaudeCredentialStore {
    static let shared = ClaudeCredentialStore()
    private var cached: ClaudeQuotaClient.Credentials?

    fileprivate func get() -> ClaudeQuotaClient.Credentials? { cached }
    fileprivate func set(_ creds: ClaudeQuotaClient.Credentials) { cached = creds }
    fileprivate func clear() { cached = nil }

    // Atomically replace the cache with a fresh load from source. Running the load
    // inside the actor closes the window where a concurrent reader could slot a stale
    // credential in between a separate clear() and set().
    fileprivate func reload(from load: @Sendable () -> ClaudeQuotaClient.Credentials?) -> ClaudeQuotaClient.Credentials? {
        cached = load()
        return cached
    }
}

struct ClaudeQuotaClient {
    let session: URLSession
    init(session: URLSession = URLSession(configuration: .ephemeral)) { self.session = session }

    /// One Claude Code OAuth credential, read-only: Claude Code owns it and refreshes it.
    /// Only what the usage request needs is kept; the refresh token is checked, not stored.
    fileprivate struct Credentials: Sendable {
        let accessToken: String
        let expiresAt: Int64

        /// nil when the JSON has no usable pair. A logged-out Claude Code leaves the item in
        /// place with empty tokens and `expiresAt: 0`; that is "no credential", not one to refresh.
        static func parse(_ data: Data) -> Credentials? {
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let oauth = obj["claudeAiOauth"] as? [String: Any],
                  let access = oauth["accessToken"] as? String, !access.isEmpty,
                  let refresh = oauth["refreshToken"] as? String, !refresh.isEmpty,
                  let expires = (oauth["expiresAt"] as? NSNumber)?.int64Value
            else { return nil }
            return Credentials(accessToken: access, expiresAt: expires)
        }
    }

    private enum ResetsAt: Decodable {
        case iso(String)
        case epochMs(Double)
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self) { self = .iso(s) }
            else { self = .epochMs(try c.decode(Double.self)) }
        }
        var date: Date? {
            switch self {
            case .iso(let s):
                // The usage endpoint returns fractional seconds ("2026-07-03T00:30:00.282668+00:00");
                // the default formatter rejects those, so try the fractional form first.
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = formatter.date(from: s) { return date }
                formatter.formatOptions = [.withInternetDateTime]
                return formatter.date(from: s)
            case .epochMs(let ms): return Date(timeIntervalSince1970: ms / 1000)
            }
        }
    }

    private struct Window: Decodable {
        let utilization: Double
        let resetsAt: ResetsAt
    }

    private struct UsageResponse: Decodable {
        let fiveHour: Window?
        let sevenDay: Window?
    }

    private enum FetchOutcome {
        case success((session: UsageLimit?, week: UsageLimit?))
        case authFailure // 401/403: the access token is no longer accepted.
        case expired // still expired after validAccessToken re-read it: another read would not help.
        case otherFailure // network/decoding/5xx: reloading credentials would not help.
    }

    func fetchLimits() async -> (session: UsageLimit?, week: UsageLimit?) {
        guard let creds = await currentCredentials() else { return (nil, nil) }
        switch await attemptFetch(creds) {
        case .success(let limits):
            return limits
        case .authFailure:
            // Claude Code likely rotated the OAuth token out from under our cache
            // (revoked access token). Drop the cached copy, re-read from source
            // (file → Keychain, which CC has updated), and retry exactly once.
            // No retry on non-auth failures.
            guard let fresh = await reloadCredentials() else { return (nil, nil) }
            if case .success(let limits) = await attemptFetch(fresh) { return limits }
            return (nil, nil)
        case .expired:
            // TODO: show «Откройте Claude Code, чтобы обновить вход» (a later step).
            return (nil, nil)
        case .otherFailure:
            return (nil, nil)
        }
    }

    private func attemptFetch(_ creds: Credentials) async -> FetchOutcome {
        guard let token = await validAccessToken(creds) else { return .expired }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/2.1.69", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .otherFailure }
            if http.statusCode == 401 || http.statusCode == 403 { return .authFailure }
            guard (200..<300).contains(http.statusCode) else { return .otherFailure }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let decoded = try decoder.decode(UsageResponse.self, from: data)
            let sessionLimit = decoded.fiveHour.map { UsageLimit(used: $0.utilization, limit: 100, resetsAt: $0.resetsAt.date) }
            let weekLimit = decoded.sevenDay.map { UsageLimit(used: $0.utilization, limit: 100, resetsAt: $0.resetsAt.date) }
            return .success((sessionLimit, weekLimit))
        } catch {
            return .otherFailure
        }
    }

    private func currentCredentials() async -> Credentials? {
        if let cached = await ClaudeCredentialStore.shared.get() { return cached }
        guard let loaded = Self.loadCredentialsFromSource() else { return nil }
        await ClaudeCredentialStore.shared.set(loaded)
        return loaded
    }

    // Force a re-read from source, bypassing the in-memory cache. Called after an auth
    // failure so a token rotated by Claude Code is picked up without an app restart.
    // The invalidate-and-reload is a single atomic actor operation (see reload(from:)).
    private func reloadCredentials() async -> Credentials? {
        await ClaudeCredentialStore.shared.reload(from: { Self.loadCredentialsFromSource() })
    }

    // File first never prompts; Keychain only as fallback. On the Keychain path, read the
    // freshest "Claude Code-credentials*" item: newer Claude Code stores its token under a
    // per-install hash suffix and no longer updates the un-suffixed item.
    private static func loadCredentialsFromSource() -> Credentials? {
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/.credentials.json")
        if let data = try? Data(contentsOf: path), let parsed = Credentials.parse(data) {
            return parsed
        }
        guard let item = KeychainReader.freshestGenericPassword(
            servicePrefix: "Claude Code-credentials", readSecret: ClaudeKeychainStore.read
        ) else { return nil }
        return Credentials.parse(Data(item.secret.utf8))
    }

    private func validAccessToken(_ creds: Credentials) async -> String? {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        if creds.expiresAt > nowMs { return creds.accessToken }
        // Claude Code may already have refreshed its login: read it again.
        let reloaded = await reloadCredentials()
        if let reloaded, reloaded.expiresAt > nowMs { return reloaded.accessToken }
        // Expired: Claude Code refreshes its own login. Skerry used to spend the shared
        // refresh token and write the rotated pair back into Claude Code's file or
        // Keychain item; when both refreshed the same pair one of them was logged out,
        // and Skerry had no business writing another app's credentials at all.
        return nil
    }
}
