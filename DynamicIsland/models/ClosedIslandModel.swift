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

import Combine
import CoreGraphics
import Defaults
import Foundation

/// Where a click opens the closed island and a hover on it stays. The
/// hover itself starts on the drawn island (its own `.onHover`): the "ears"
/// beside the notch (docs/PLAN-DESIGN.md §3.1) needed every pointer move of
/// the session and were removed for energy (docs/perf/REPORT-energy.md §9).
enum IslandHoverZone {
    static let below: CGFloat = 6

    /// The closed island as drawn: centred on the screen, shifted by
    /// `xOffset` when a live activity steps aside from the menus, hanging
    /// from the top edge.
    static func notchRect(screenFrame: CGRect, width: CGFloat, height: CGFloat, xOffset: CGFloat = 0) -> CGRect {
        CGRect(x: screenFrame.midX - width / 2 + xOffset, y: screenFrame.maxY - height, width: width, height: height)
    }

    /// Where a click opens the island and a hover on it stays: the notch and
    /// the strip below it. No margin beside it (upstream had 12 pt either
    /// side): macOS lays the menu titles out flush against the camera, so a
    /// side margin lay on the nearest title, and a pointer resting there kept
    /// the hover (the island opened after the delay) and a click there opened
    /// the island along with the menu (owner, 22.10.2026: only the island
    /// itself opens it). Below the notch there is no menu, so the strip stays.
    static func clickArea(around notch: CGRect) -> CGRect {
        CGRect(x: notch.minX, y: notch.minY - below, width: notch.width, height: notch.height + below)
    }

    /// Inclusive on every edge: a pointer parked on the top pixel is inside.
    static func contains(_ rect: CGRect, _ point: CGPoint) -> Bool {
        point.x >= rect.minX && point.x <= rect.maxX && point.y >= rect.minY && point.y <= rect.maxY
    }

    /// A click opens the island only on the island itself: a click beside
    /// it belongs to the menu bar item under it.
    static func clickOpens(onNotch: Bool, overIsland: Bool) -> Bool {
        onNotch || overIsland
    }
}

/// The wings beside the notch. The island is centred on the camera, so a
/// right wing wider than the left (a scrolling title, a timer) pushed the
/// artwork under the camera housing; the left wing now matches it.
enum IslandWings {
    static func symmetricWidth(left: CGFloat, right: CGFloat) -> CGFloat {
        max(left, right)
    }
}

/// The closed island no longer shows the shelf all the time: adding files
/// flashes "+N" for a moment instead (docs/PLAN-DESIGN.md §3.1).
@MainActor
final class ShelfFlashModel: ObservableObject {
    struct Flash: Equatable {
        let id = UUID()
        let added: Int
    }

    static let shared = ShelfFlashModel()
    static let duration: TimeInterval = 2.5

    @Published private(set) var flash: Flash?

    /// Items seen so far; nil until the first look, so loading the saved
    /// shelf at launch does not flash.
    private var known: Set<UUID>?
    private var clearWork: DispatchWorkItem?
    private var subscription: AnyCancellable?

    init() {}

    /// Follows the shelf; called once at launch.
    func start(items: AnyPublisher<[UUID], Never>) {
        guard subscription == nil else { return }
        subscription = items.receive(on: DispatchQueue.main).sink { [weak self] ids in
            self?.itemsChanged(ids)
        }
    }

    func itemsChanged(_ ids: [UUID]) {
        let current = Set(ids)
        defer { known = current }
        let added = Self.added(previous: known, current: current)
        guard added > 0 else { return }
        clearWork?.cancel()
        flash = Flash(added: added)
        let work = DispatchWorkItem { [weak self] in self?.flash = nil }
        clearWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.duration, execute: work)
    }

    func clear() {
        clearWork?.cancel()
        flash = nil
    }

    /// Items that were not there before; none on the first look.
    nonisolated static func added(previous: Set<UUID>?, current: Set<UUID>) -> Int {
        guard let previous else { return 0 }
        return current.subtracting(previous).count
    }
}

/// "Standard" or "Compact" island (docs/PLAN-DESIGN.md §3.10). Compact
/// replaces upstream's minimalistic mode, which hid the tabs and every way
/// back to the settings: it shows fewer tabs and gives the player the whole
/// width, while the tabs and the "…" menu always stay.
enum IslandLayout: String, CaseIterable, Codable, Defaults.Serializable, Identifiable {
    case standard
    case compact

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return String(localized: "Standard")
        case .compact: return String(localized: "Compact")
        }
    }

    /// The tabs a compact island keeps.
    static let compactTabs: Set<NotchTab> = [.nowPlaying, .screenshots, .clipboard, .shelf]

    func keeps(_ tab: NotchTab) -> Bool {
        self == .standard || Self.compactTabs.contains(tab)
    }

    /// Upstream's minimalistic mode becomes Compact once; the old switch is
    /// never on again.
    static func migratedFromMinimalistic(minimalistic: Bool, current: IslandLayout) -> IslandLayout {
        minimalistic ? .compact : current
    }
}
