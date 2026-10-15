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

import AppKit
import Defaults
import SwiftUI
import UniformTypeIdentifiers

/// Privacy controls of the clipboard settings: pause, disk persistence,
/// age-based cleanup and the apps whose copies are never recorded.
struct ClipboardPrivacySettingsSections: View {
    @Default(.clipboardAutoClearHours) private var autoClearHours
    @Default(.clipboardIgnoredApps) private var ignoredApps
    @Default(.clipboardPersistPinned) private var persistPinned

    private static let autoClearChoices: [(hours: Int, label: LocalizedStringKey)] = [
        (0, "Never"), (1, "After 1 hour"), (6, "After 6 hours"), (12, "After 12 hours"),
        (24, "After 24 hours"), (48, "After 2 days"), (168, "After 7 days"),
    ]

    /// Maps a row title to its settings-search highlight id (the tab enum is
    /// private to SettingsView).
    let highlightID: (String) -> String

    var body: some View {
        Section {
            Defaults.Toggle(key: .clipboardHistoryPaused) {
                Text("Pause Clipboard History")
            }
            .settingsHighlight(id: highlightID("Pause Clipboard History"))

            Defaults.Toggle(key: .persistClipboardHistory) {
                Text("Save History Across Restarts")
            }
            .settingsHighlight(id: highlightID("Save History Across Restarts"))

            Defaults.Toggle(key: .clipboardPersistPinned) {
                Text("Save pinned items only")
            }
            .settingsHighlight(id: highlightID("Save pinned items only"))
            if persistPinned {
                Label("Pinned items, including pictures, are written to disk in Skerry's data folder.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Defaults.Toggle(key: .clipboardOneTimeCodeExpiry) {
                Text("Remove one-time codes after 2 minutes")
            }
            .settingsHighlight(id: highlightID("Remove one-time codes after 2 minutes"))

            Picker("Remove Items", selection: $autoClearHours) {
                ForEach(Self.autoClearChoices, id: \.hours) { choice in
                    Text(choice.label).tag(choice.hours)
                }
            }
            .pickerStyle(.menu)
            .settingsHighlight(id: highlightID("Remove Items"))
        } header: {
            Text("Privacy")
        } footer: {
            Text("While paused, nothing you copy is added to the history; a pause icon shows in the island. When saving is off, history is kept in memory for this session only and is never written to disk; turning it off also erases history that was already saved. Pinned items also stay in memory unless “Save pinned items only” is on; they are not removed by age. One-time codes are copies of 4 to 8 digits only.")
        }

        Section {
            ForEach(ignoredApps, id: \.self) { bundleID in
                HStack {
                    Image(nsImage: Self.icon(for: bundleID))
                        .resizable()
                        .frame(width: 18, height: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Self.displayName(for: bundleID))
                        Text(bundleID)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        ignoredApps.removeAll { $0 == bundleID }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Remove")
                }
            }

            HStack {
                Button("Add App…") { addApp() }
                Spacer()
                Button("Restore Defaults") {
                    ignoredApps = ClipboardCapturePolicy.defaultIgnoredApps
                }
                .disabled(ignoredApps == ClipboardCapturePolicy.defaultIgnoredApps)
            }
        } header: {
            Text("Ignored Apps")
        } footer: {
            Text("Copies made while one of these apps is in front are not recorded. Copies that password managers mark as concealed or transient are never recorded, from any app.")
        }
        .settingsHighlight(id: highlightID("Ignored Apps"))
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Ignore")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundleID = Bundle(url: url)?.bundleIdentifier, !ignoredApps.contains(bundleID) else { continue }
            ignoredApps.append(bundleID)
        }
    }

    private static func appURL(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    private static func displayName(for bundleID: String) -> String {
        guard let url = appURL(for: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private static func icon(for bundleID: String) -> NSImage {
        guard let url = appURL(for: bundleID) else {
            return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
