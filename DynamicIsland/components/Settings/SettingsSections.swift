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

import SwiftUI

/// The eight sections of Settings instead of twenty-three tabs
/// (docs/PLAN-DESIGN.md §3.8). Each holds one or more of the old pages, by
/// their raw value, and shows them as a segmented choice on top.
enum SettingsSectionLayout: String, CaseIterable, Identifiable {
    case general
    case island
    case music
    case notifications
    case lockScreen
    case productivity
    case tools
    case advanced

    var id: String { rawValue }

    var pageIDs: [String] {
        switch self {
        case .general: return ["general", "shortcuts", "about"]
        case .island: return ["layout", "appearance"]
        case .music: return ["media", "devices"]
        case .notifications: return ["liveActivities", "hudAndOSD", "battery"]
        case .lockScreen: return ["lockScreen"]
        case .productivity: return ["clipboard", "screenshots", "shelf", "notes", "timer", "calendar"]
        case .tools: return ["colorPicker", "terminal", "stats", "screenAssistant", "downloads"]
        case .advanced: return ["extensions"]
        }
    }

    var title: String {
        switch self {
        case .general: return String(localized: "General")
        case .island: return String(localized: "Island")
        case .music: return String(localized: "Music")
        case .notifications: return String(localized: "Notifications and HUD")
        case .lockScreen: return String(localized: "Lock Screen")
        case .productivity: return String(localized: "Productivity")
        case .tools: return String(localized: "Tools")
        case .advanced: return String(localized: "Advanced")
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .island: return "capsule.portrait"
        case .music: return "music.note"
        case .notifications: return "bell.badge"
        case .lockScreen: return "lock"
        case .productivity: return "tray.full"
        case .tools: return "wrench.and.screwdriver"
        case .advanced: return "puzzlepiece.extension"
        }
    }

    var tint: Color {
        switch self {
        case .general: return Color(rgb: 0x8E8E93)
        case .island: return Color(rgb: 0x0A84FF)
        case .music: return Color(rgb: 0xFF375F)
        case .notifications: return Color(rgb: 0xFF9F0A)
        case .lockScreen: return Color(rgb: 0x5E5CE6)
        case .productivity: return Color(rgb: 0x30D158)
        case .tools: return Color(rgb: 0x64D2FF)
        case .advanced: return Color(rgb: 0x636366)
        }
    }

    /// The section a page belongs to.
    static func section(forPage id: String) -> SettingsSectionLayout? {
        allCases.first { $0.pageIDs.contains(id) }
    }

    /// Search matches the English name and the name in the app's language
    /// (upstream matched English only).
    static func matches(_ text: String, query: String, bundle: Bundle = .main) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let localized = bundle.localizedString(forKey: text, value: text, table: nil)
        return [text, localized].contains { $0.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}
