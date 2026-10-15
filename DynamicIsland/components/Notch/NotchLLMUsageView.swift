/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
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

import SwiftUI
import Defaults

enum AntigravityPool: String, CaseIterable {
    case gemini = "Gemini"
    case claude = "Claude"
}

struct NotchLLMUsageView: View {
    @ObservedObject private var manager = LLMUsageManager.shared
    @State private var antigravityPool: AntigravityPool = .gemini
    // Observed, so hiding a provider from its card takes it off the row.
    @Default(.enableClaudeProvider) private var claudeOn
    @Default(.enableCodexProvider) private var codexOn
    @Default(.enableCursorProvider) private var cursorOn
    @Default(.enableAntigravityProvider) private var antigravityOn
    @Default(.enableNewAPIProvider) private var newAPIOn

    private func isEnabled(_ provider: ProviderID) -> Bool {
        switch provider {
        case .claude: return claudeOn
        case .codex: return codexOn
        case .cursor: return cursorOn
        case .antigravity: return antigravityOn
        case .newAPI: return newAPIOn
        }
    }

    private var enabledProviders: [ProviderID] {
        ProviderID.allCases.filter { isEnabled($0) }
    }

    var body: some View {
        Group {
            if enabledProviders.isEmpty {
                // All off used to leave the tab blank.
                DSEmptyState(
                    symbol: "chart.bar.doc.horizontal",
                    title: String(localized: "No services turned on"),
                    message: String(localized: "Turn on Claude, Codex, Cursor or another service in Settings → Tools → Stats."),
                    actionTitle: String(localized: "Open Settings"),
                    action: { SettingsWindowController.shared.showWindow() }
                )
            } else {
                VStack(spacing: 6) {
                    UsageRefreshBar(lastUpdated: manager.lastUpdated, isRefreshing: manager.isRefreshing) {
                        manager.refreshAll(force: true)
                    }
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(enabledProviders) { provider in
                            card(for: provider)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .environment(\.colorScheme, .dark)
        .onAppear { manager.refreshAll() }
        .onChange(of: enabledProviders) { old, new in
            // A provider switched on fetches at once; hiding one fetches nothing.
            if !Set(new).subtracting(old).isEmpty { manager.refreshAll(force: true) }
        }
    }

    @ViewBuilder
    private func card(for provider: ProviderID) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(provider.displayName)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .layoutPriority(1)
                // Subscription plan badge (e.g. "Max 5x"). Only set for Claude; nil elsewhere.
                if case .success(let snap) = manager.results[provider] ?? .loading, let plan = snap.plan {
                    Text(plan)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.white.opacity(0.12), in: Capsule())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if provider == .antigravity {
                    Picker("", selection: $antigravityPool) {
                        Text("Gemini").tag(AntigravityPool.gemini)
                        Text("Claude").tag(AntigravityPool.claude)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                    .controlSize(.mini)
                }
            }
            switch manager.results[provider] ?? .loading {
            case .loading:
                ProgressView().controlSize(.small)
            case .notFound:
                Text("Not found on this Mac").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Button(String(localized: "Hide")) { Defaults[provider.enabledKey] = false }
                    .buttonStyle(DSButtonStyle(kind: .secondary, height: 22))
                    .help(String(localized: "Turn this service off; it can be turned on again in Settings → Tools → Stats."))
            case .failure(let reason):
                Text(reason).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            case .success(let snap):
                if provider == .newAPI {
                    newAPISuccess(snap)
                } else {
                    success(snap, provider: provider)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        // Stretch every card to the height the panel offers so the row stays uniform
        // (the intent behind the former fixed card height) without a hard-coded size
        // that either clips content or leaves blank space.
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func success(_ snap: UsageSnapshot, provider: ProviderID) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if provider == .antigravity {
                antigravitySuccess(snap)
            } else if snap.sessionLimit == nil && snap.weekLimit == nil {
                if provider != .cursor {
                    window("Today", snap.today, prominent: true)
                    window("Week", snap.week)
                    window("Session", snap.session)
                }
                Text("quota unavailable").font(.caption2).foregroundStyle(.secondary.opacity(0.7))
            } else {
                if provider == .cursor {
                    if let limit = snap.sessionLimit { quotaGauge("Cursor Models", limit) }
                    if let limit = snap.weekLimit { quotaGauge("Other Models", limit) }
                } else {
                    if let limit = snap.sessionLimit { quotaGauge("Session", limit) }
                    if let limit = snap.weekLimit { quotaGauge("Week", limit) }
                    VStack(alignment: .leading, spacing: 2) {
                        window("Today", snap.today, compact: true)
                        window("Week", snap.week, compact: true)
                    }
                }
            }
        }
    }

    private func antigravitySuccess(_ snap: UsageSnapshot) -> some View {
        let isGemini = antigravityPool == .gemini
        let targetPool = isGemini ? "gemini" : "claude"
        
        // Filter models by pool
        let sessionModel = snap.models.first { $0.model == "Session" && $0.pool == targetPool }
        let weeklyModel = snap.models.first { $0.model == "Weekly" && $0.pool == targetPool }
        
        // Helper to create UsageLimit from model
        func limitFromModel(_ model: ModelUsage?) -> UsageLimit? {
            guard let model = model else { return nil }
            let fraction = model.totals.costUSD
            let usedPct = (1 - max(0, min(1, fraction))) * 100
            return UsageLimit(used: usedPct, limit: 100, resetsAt: model.resetsAt)
        }
        
        return VStack(alignment: .leading, spacing: 6) {
            if let limit = limitFromModel(sessionModel) {
                quotaGauge("Session", limit)
            }
            if let limit = limitFromModel(weeklyModel) {
                quotaGauge("Weekly", limit)
            }
            
            // Token counts and estimated cost read from the language server's
            // conversation history (all pools; Antigravity does not split them).
            VStack(alignment: .leading, spacing: 4) {
                window("Today", snap.today, compact: true)
                window("Week", snap.week, compact: true)
            }
        }
    }

    private func newAPISuccess(_ snap: UsageSnapshot) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(snap.newAPIAccounts) { account in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(account.name)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Spacer()
                            if account.errorMessage != nil {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                    .help(account.errorMessage ?? "New API account has an error")
                            }
                        }

                        if let errorMessage = account.errorMessage,
                           account.balanceQuota == nil {
                            Text(errorMessage)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        } else {
                            quotaRow("Balance", account.balanceQuota, prominent: true)
                            quotaRow("Used", account.usedQuota)
                            quotaRow("Today", account.todayQuota)
                            quotaRow("Week", account.weekQuota)
                            HStack(spacing: 12) {
                                metric("RPM", account.currentRPM)
                                metric("TPM", account.currentTPM)
                                metric("Requests", account.requestCount)
                            }
                            if let errorMessage = account.errorMessage {
                                Text(errorMessage)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.bottom, 2)
                    .overlay(alignment: .bottom) {
                        if account.id != snap.newAPIAccounts.last?.id {
                            Rectangle()
                                .fill(.white.opacity(0.1))
                                .frame(height: 1)
                        }
                    }
                }
            }
        }
        .frame(height: 135)
    }

    private func quotaRow(_ label: LocalizedStringKey, _ value: Int?, prominent: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            Text(value.map(quota) ?? "-")
                .font(.system(size: prominent ? 15 : 11, weight: prominent ? .bold : .semibold, design: .rounded))
                .monospacedDigit()
            Spacer()
        }
    }

    private func metric(_ label: String, _ value: Int?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value.map(quota) ?? "-")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private func quotaGauge(_ label: LocalizedStringKey, _ limit: UsageLimit) -> some View {
        let usedPct = Int(limit.used.rounded())
        let leftPct = max(0, 100 - usedPct)
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if let resets = resetsIn(limit.resetsAt) {
                    Text(resets).font(.caption2).foregroundStyle(.secondary)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15))
                    Capsule().fill(gaugeTint(limit.fraction)).frame(width: max(4, geo.size.width * limit.fraction))
                }
            }
            .frame(height: 6)
            HStack {
                Text("\(usedPct)% used").font(.caption2).monospacedDigit()
                Spacer()
                Text("\(leftPct)% left").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }

    private func gaugeTint(_ fraction: Double) -> Color {
        if fraction > 0.95 { return .red }
        if fraction > 0.9 { return .orange }
        return .accentColor
    }

    private func resetsIn(_ date: Date?) -> String? {
        guard let date else { return nil }
        let seconds = Int(date.timeIntervalSinceNow)
        guard seconds > 0 else { return nil }
        let days = seconds / 86_400
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if days > 0 {
            return "resets in \(days)d \(hours % 24)h \(minutes)m"
        }
        return hours > 0 ? "resets in \(hours)h \(minutes)m" : "resets in \(minutes)m"
    }

    private func window(_ label: LocalizedStringKey, _ totals: UsageTotals, prominent: Bool = false, compact: Bool = false) -> some View {
        let displayValue: String
        if totals.isPercentage {
            displayValue = "\(totals.totalTokens)%"
        } else {
            displayValue = tokens(totals.totalTokens)
        }
        
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: compact ? 56 : 48, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(displayValue)
                .font(.system(size: compact ? 11 : (prominent ? 17 : 13), weight: prominent ? .bold : .semibold, design: .rounded))
                .monospacedDigit()
            Spacer(minLength: 4)
            if totals.isPercentage {
                // Quota providers store the remaining fraction in costUSD; it is not money.
                let leftPct = Int((max(0, min(1, totals.costUSD)) * 100).rounded())
                Text("\(leftPct)% left")
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            } else {
                Text(costLabel(totals))
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                    .help(costHelp(totals))
            }
        }
    }

    /// Cost is an estimate computed from local token counts against the API price
    /// table — not a subscription bill. When some models used have no entry in the
    /// table we cannot price them: show "\(money)+" when a partial amount is known,
    /// and an explicit "est. n/a" instead of a misleading "$0.00+" when nothing is.
    private func costLabel(_ totals: UsageTotals) -> String {
        guard totals.hasUnpricedModel else { return money(totals.costUSD) }
        return totals.costUSD > 0 ? money(totals.costUSD) + "+" : "est. n/a"
    }

    private func costHelp(_ totals: UsageTotals) -> String {
        if totals.hasUnpricedModel {
            return "Estimated API-equivalent cost from local token counts (not your subscription bill). Some models used do not have usable pricing, so this is partial or unavailable."
        }
        return "Estimated API-equivalent cost from local token counts (cache reads and writes priced at the provider's cache rates), not your subscription bill."
    }

    private func tokens(_ n: Int) -> String {
        switch n {
        case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
        case 1_000...: return String(format: "%.1fk", Double(n) / 1_000)
        default: return "\(n)"
        }
    }

    private func quota(_ n: Int) -> String {
        switch n {
        case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
        case 1_000...: return String(format: "%.1fk", Double(n) / 1_000)
        default: return "\(n)"
        }
    }

    // Locale-aware formatting pinned to USD — amounts come from the USD pricing table, so the currency code stays fixed.
    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f
    }()

    private func money(_ v: Double) -> String {
        Self.currencyFormatter.string(from: v as NSNumber) ?? String(format: "$%.2f", v)
    }
}

/// "Updated 2 min ago ⟳" above the cards. Refreshing used to happen only
/// when the tab appeared, at most once a minute, with no way to ask.
struct UsageRefreshBar: View {
    let lastUpdated: Date?
    let isRefreshing: Bool
    var onRefresh: () -> Void = {}

    var body: some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)
            TimelineView(.periodic(from: .now, by: 30)) { context in
                if let text = Self.updatedText(lastUpdated: lastUpdated, now: context.date) {
                    Text(text)
                        .font(DS.Typeface.caption)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .lineLimit(1)
                }
            }
            if isRefreshing {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 20, height: 16)
            } else {
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 20, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(DS.Palette.textSecondary)
                .help(String(localized: "Refresh"))
                .accessibilityLabel(Text("Refresh"))
            }
        }
        .frame(height: 16)
    }

    /// nil before the first refresh; "just now" for the first minute.
    static func updatedText(lastUpdated: Date?, now: Date, locale: Locale = .current) -> String? {
        guard let lastUpdated else { return nil }
        guard now.timeIntervalSince(lastUpdated) >= 60 else { return String(localized: "Updated just now") }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = locale
        return String(format: String(localized: "Updated %@"), formatter.localizedString(for: lastUpdated, relativeTo: now))
    }
}
