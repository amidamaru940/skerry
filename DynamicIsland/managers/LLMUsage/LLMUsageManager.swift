import Foundation
import SwiftUI
import Defaults

@MainActor
final class LLMUsageManager: ObservableObject {
    static let shared = LLMUsageManager()

    @Published var results: [ProviderID: UsageResult] = [:]
    @Published var isRefreshing = false
    /// When the last refresh finished; nil before the first.
    @Published private(set) var lastUpdated: Date?

    private let injectedProviders: [UsageProvider]? // overrides the flag-based default when non-nil
    private var lastRefresh: Date = .distantPast
    private static let minRefreshInterval: TimeInterval = 60

    init(providers: [UsageProvider]? = nil) {
        self.injectedProviders = providers
    }

    private static let allProviders: [UsageProvider] = [ClaudeUsageProvider(), CodexUsageProvider(), CursorUsageProvider(), AntigravityUsageProvider(), NewAPIUsageProvider()]

    private var enabledProviders: [UsageProvider] {
        if let injectedProviders { return injectedProviders }
        return Self.allProviders.filter { Defaults[$0.id.enabledKey] }
    }

    func refreshAll(force: Bool = false) {
        // The providers read Claude/Codex/Cursor/Gemini credentials (files and
        // Keychain) and call their APIs; none of that may run while off.
        guard Defaults[.enableLLMUsageFeature] else { return }
        guard !isRefreshing else { return }
        guard force || Date().timeIntervalSince(lastRefresh) >= Self.minRefreshInterval else { return }
        lastRefresh = Date()
        isRefreshing = true
        let providers = enabledProviders
        let enabledIDs = Set(providers.map { $0.id })
        results = results.filter { enabledIDs.contains($0.key) } // drop disabled providers' stale results
        for p in providers where results[p.id] == nil { results[p.id] = .loading }
        Task { await runRefresh(providers: providers) }
    }

    private func runRefresh(providers: [UsageProvider]) async {
        let now = Date()
        await withTaskGroup(of: (ProviderID, UsageResult).self) { group in
            for provider in providers {
                group.addTask {
                    do { return (provider.id, .success(try await provider.fetchSnapshot(now: now))) }
                    catch { return (provider.id, Self.result(for: error)) }
                }
            }
            for await (id, result) in group { results[id] = result }
        }
        isRefreshing = false
        lastUpdated = Date()
    }

    /// A provider that is not on this Mac is not an error to read out;
    /// anything else keeps its reason.
    nonisolated static func result(for error: Error) -> UsageResult {
        if case UsageError.notFound = error { return .notFound }
        return .failure(error.localizedDescription)
    }
}
