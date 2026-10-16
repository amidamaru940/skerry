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

/// "Next": the next few events today and tomorrow, one line each, instead
/// of upstream's month strip and day list (docs/PLAN-DESIGN.md §3.3).
enum NextEvents {
    static let limit = 3
    /// Beside the compact one-row player: two lines fit its height.
    static let compactLimit = 2

    enum Day: Equatable { case today, tomorrow }

    enum State: Equatable {
        /// No calendar access yet: one line and one button.
        case noAccess
        /// Nothing left today or tomorrow.
        case free
        case events([EventModel])

        var shownEvents: Int {
            if case .events(let events) = self { return events.count }
            return 0
        }
    }

    /// Events still running or to come, today and tomorrow, earliest first:
    /// ended events, completed reminders and (when hidden) all-day events
    /// are left out.
    static func pick(
        _ events: [EventModel],
        now: Date,
        hideAllDay: Bool,
        calendar: Calendar = .current,
        limit: Int = limit
    ) -> [EventModel] {
        let startOfToday = calendar.startOfDay(for: now)
        guard let endOfTomorrow = calendar.date(byAdding: .day, value: 2, to: startOfToday) else { return [] }
        return events
            .filter { event in
                if case .reminder(let completed) = event.type, completed { return false }
                if event.isAllDay && hideAllDay { return false }
                return event.end > now && event.start < endOfTomorrow
            }
            // Calendar order: today before tomorrow, all-day events first.
            .sorted { sortKey($0, now: now, calendar: calendar) < sortKey($1, now: now, calendar: calendar) }
            .prefix(limit)
            .map { $0 }
    }

    private static func sortKey(_ event: EventModel, now: Date, calendar: Calendar) -> (Int, Int, Date) {
        (day(of: event, now: now, calendar: calendar) == .today ? 0 : 1, event.isAllDay ? 0 : 1, event.start)
    }

    static func state(authorized: Bool, events: [EventModel], now: Date, hideAllDay: Bool, calendar: Calendar = .current, limit: Int = limit) -> State {
        guard authorized else { return .noAccess }
        let next = pick(events, now: now, hideAllDay: hideAllDay, calendar: calendar, limit: limit)
        return next.isEmpty ? .free : .events(next)
    }

    /// Whether "Next" offers to show reminders too: calendar access is there,
    /// reminders are a separate permission nobody has answered yet, and a line
    /// is free for the offer. Skerry never asked for reminders, so they were
    /// missing from "Next" with nothing to say why.
    static func offersReminders(calendarAuthorized: Bool, remindersUndecided: Bool, shownEvents: Int, limit: Int) -> Bool {
        calendarAuthorized && remindersUndecided && shownEvents < limit
    }

    /// Today or tomorrow, by the day the event is still on at `now`.
    static func day(of event: EventModel, now: Date, calendar: Calendar = .current) -> Day {
        let shown = max(event.start, now)
        return calendar.isDate(shown, inSameDayAs: now) ? .today : .tomorrow
    }

    enum Time: Equatable {
        case now
        case allDay
        case at(Date)
    }

    static func time(of event: EventModel, now: Date) -> Time {
        if event.isAllDay { return .allDay }
        return event.start <= now ? .now : .at(event.start)
    }
}

/// What the "Now" tab shows (docs/PLAN-DESIGN.md §3.3).
enum NowTabLayout: Equatable {
    /// The player, with "Next" beside it when the calendar is on.
    case player(next: Bool)
    /// Nothing playing: the last track, greyed, with ▶, and "Next" across.
    case idle
    /// No player to show: "Next" across the whole width.
    case nextOnly
    /// No player and no calendar.
    case nothing

    static func resolve(playerShown: Bool, isPlaying: Bool, playerIdle: Bool, calendarOn: Bool, compact: Bool) -> NowTabLayout {
        // Compact draws its own one-row player, with "Next" in the same row
        // (CompactPlayerRow), so there is no card beside it here.
        let next = calendarOn && !compact
        if playerShown {
            if next && !isPlaying && playerIdle { return .idle }
            return .player(next: next)
        }
        return calendarOn ? .nextOnly : .nothing
    }

    /// Whether "Next" is drawn yet. Beside the player it waits for the tab's
    /// first appearance (the deferral), so the player lays out first. Alone
    /// it has nothing to wait for -- and must not: the deferral starts when
    /// something on the tab appears, and a tab holding only a gated "Next"
    /// had nothing to appear, so it stayed empty whenever no music played.
    func showsNext(deferralDone: Bool) -> Bool {
        switch self {
        case .nextOnly: return true
        case .player(let next): return next && deferralDone
        case .idle: return deferralDone
        case .nothing: return false
        }
    }
}

/// The player's buttons: the transport always, the rest (shuffle, repeat,
/// output, lyrics, favourite, volume) only while the pointer is over the
/// player, on either side of it.
enum PlayerControlsLayout {
    struct Split: Equatable {
        var leading: [MusicControlButton]
        var transport: [MusicControlButton]
        var trailing: [MusicControlButton]
    }

    static let transportControls: Set<MusicControlButton> = [.trackBackward, .seekBackward, .playPause, .trackForward, .seekForward]

    /// Keeps the user's slot order; the extras are shared out to the sides,
    /// the first half on the left. The output picker and lyrics join the
    /// extras when they are not in a slot already.
    static func split(_ slots: [MusicControlButton], addingOutput: Bool = false, addingLyrics: Bool = false) -> Split {
        let transport = slots.filter { transportControls.contains($0) }
        var extras = slots.filter { $0 != .none && !transportControls.contains($0) }
        if addingOutput && !extras.contains(.mediaOutput) && !extras.contains(.airPlay) {
            extras.append(.mediaOutput)
        }
        if addingLyrics && !extras.contains(.lyrics) {
            extras.append(.lyrics)
        }
        let leadingCount = (extras.count + 1) / 2
        return Split(
            leading: Array(extras.prefix(leadingCount)),
            transport: transport.isEmpty ? [.trackBackward, .playPause, .trackForward] : transport,
            trailing: Array(extras.dropFirst(leadingCount))
        )
    }
}
