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

/// The filter chips of the Clipboard tab.
enum ClipboardFilter: String, CaseIterable, Identifiable {
    case all, text, links, images, files

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return String(localized: "All")
        case .text: return String(localized: "Text")
        case .links: return String(localized: "Links")
        case .images: return String(localized: "Images")
        case .files: return String(localized: "Files")
        }
    }

    func matches(_ type: ClipboardItemType) -> Bool {
        switch self {
        case .all: return true
        case .text: return type == .text || type == .rtf || type == .unknown
        case .links: return type == .url
        case .images: return type == .image
        case .files: return type == .file
        }
    }
}

enum ClipboardFiltering {
    /// Items of the chosen kind whose full text, preview or file names contain
    /// the query (case- and diacritic-insensitive). An empty query matches all.
    static func apply(_ items: [ClipboardItem], filter: ClipboardFilter, query: String) -> [ClipboardItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { item in
            guard filter.matches(item.type) else { return false }
            guard !needle.isEmpty else { return true }
            let haystacks = [item.stringData, item.preview]
                + (item.fileURLs ?? []).map { URL(string: $0)?.lastPathComponent }
            return haystacks.contains { text in
                guard let text else { return false }
                return text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
    }
}

/// "20:41" today, "Yesterday 18:02", "14 Oct 09:15" otherwise.
enum DayTimeLabel {
    static func make(for date: Date, now: Date = Date(), calendar: Calendar = .current,
                     bundle: Bundle = .main, locale: Locale = .current) -> String {
        let time = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale))
        if calendar.isDate(date, inSameDayAs: now) { return time }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "\(bundle.localizedString(forKey: "Yesterday", value: "Yesterday", table: nil)) \(time)"
        }
        return "\(date.formatted(Date.FormatStyle().day().month(.abbreviated).locale(locale))) \(time)"
    }

    /// The row's short form (Buffer v3): «12:31 PM» today, «Вчера»
    /// yesterday, «21 окт.» before; the full one is in the row's tooltip.
    static func compact(for date: Date, now: Date = Date(), calendar: Calendar = .current,
                        bundle: Bundle = .main, locale: Locale = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale))
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return bundle.localizedString(forKey: "Yesterday", value: "Yesterday", table: nil)
        }
        return date.formatted(Date.FormatStyle().day().month(.abbreviated).locale(locale))
    }
}
