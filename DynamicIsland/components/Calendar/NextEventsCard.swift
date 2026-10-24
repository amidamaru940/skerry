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
import EventKit
import SwiftUI

/// "Next" beside the player: the next two or three events today and
/// tomorrow, one line each, instead of a month strip (docs/PLAN-DESIGN.md
/// §3.3). Without calendar access: one line and one button.
struct NextEventsCard: View {
    /// A card beside the player; bare lines beside the compact one-row
    /// player; the lines under a heading when nothing plays in the compact
    /// island, which is too low for the card.
    enum Style { case card, lines, headedLines }

    /// Three beside the player; two under the "nothing playing" strip and
    /// beside the compact player.
    var limit = NextEvents.limit
    var style: Style = .card
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject private var calendarManager = CalendarManager.shared
    @Default(.hideAllDayEvents) private var hideAllDayEvents
    @Environment(\.openURL) private var openURL

    var body: some View {
        // Redrawn every minute, so "Now" and the day boundary stay right.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let state = NextEvents.state(
                authorized: calendarManager.hasCalendarAccess,
                events: calendarManager.upcomingEvents,
                now: context.date,
                hideAllDay: hideAllDayEvents,
                limit: limit
            )
            let offersReminders = NextEvents.offersReminders(
                calendarAuthorized: calendarManager.hasCalendarAccess,
                remindersUndecided: calendarManager.reminderAuthorizationStatus == .notDetermined,
                shownEvents: state.shownEvents,
                limit: limit
            )
            let remindersOffer: (() -> Void)? = offersReminders ? allowReminders : nil
            switch style {
            case .card:
                NextEventsCardContent(state: state, now: context.date, onAllowAccess: allowAccess, onAllowReminders: remindersOffer, onOpen: open)
            case .lines:
                NextEventLines(state: state, now: context.date, onAllowAccess: allowAccess, onAllowReminders: remindersOffer, onOpen: open)
            case .headedLines:
                NextEventLines(state: state, now: context.date, showsHeading: true, onAllowAccess: allowAccess, onAllowReminders: remindersOffer, onOpen: open)
                    .padding(.horizontal, 6)
            }
        }
        .onAppear { refresh() }
        .onChange(of: vm.notchState) { _, state in
            if state == .open { refresh() }
        }
    }

    private func refresh() {
        calendarManager.refreshReminderAuthorizationStatus()
        Task { await calendarManager.updateUpcomingEvents() }
    }

    /// Reminders are a permission of their own; asked on this click only.
    private func allowReminders() {
        Task {
            await calendarManager.checkReminderAuthorization()
            await calendarManager.updateUpcomingEvents(force: true)
        }
    }

    private func open(_ event: EventModel) {
        if let url = event.calendarAppURL() { openURL(url) }
    }

    /// Asks macOS for access the first time; after a refusal only System
    /// Settings can grant it.
    private func allowAccess() {
        switch calendarManager.calendarAuthorizationStatus {
        case .notDetermined:
            Task {
                await calendarManager.checkCalendarAuthorization()
                // "Next" shows reminders too, which macOS asks about apart.
                await calendarManager.checkReminderAuthorization()
                await calendarManager.updateUpcomingEvents(force: true)
            }
        default:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

/// "Next" drawn from plain values: in E a line of time, not a card
/// (docs/design/VISUAL-E.md §2.6). A vertical hairline, «ДАЛЕЕ» and the rows
/// 12 to its right; each event's dot sits on the line, the nearest event of
/// today lit in the accent. No card, no date, no calendar colours.
struct NextEventsCardContent: View {
    let state: NextEvents.State
    let now: Date
    var onAllowAccess: () -> Void = {}
    /// Set while reminders can be offered (see `NextEvents.offersReminders`).
    var onAllowReminders: (() -> Void)? = nil
    var onOpen: (EventModel) -> Void = { _ in }

    var body: some View {
        TimeLineColumn(label: String(localized: "Next")) {
            switch state {
            case .noAccess:
                VStack(alignment: .leading, spacing: 8) {
                    Text("To see your next events, allow access to the calendar.")
                        .eText(.body)
                        .foregroundStyle(DSE.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(String(localized: "Allow Access"), action: onAllowAccess)
                        .buttonStyle(SecondaryKeyStyle())
                        .fixedSize()
                }
            case .free:
                freeLine
            case .events(let events):
                eventRows(events)
            }
            if let onAllowReminders {
                RemindersOfferRow(onAllow: onAllowReminders)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var freeLine: some View {
        Text(String(localized: "Free for the rest of the day"))
            .eText(.body)
            .foregroundStyle(DSE.Palette.textSecondary)
            .lineLimit(1)
            .frame(height: DSE.Size.rowPitch, alignment: .leading)
    }

    @ViewBuilder
    private func eventRows(_ events: [EventModel]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            let firstTomorrow = events.firstIndex { NextEvents.day(of: $0, now: now) == .tomorrow }
            // The one lit dot: the nearest timed event of today.
            let current = events.firstIndex { !$0.isAllDay && NextEvents.day(of: $0, now: now) == .today }
            if firstTomorrow == 0 {
                // Nothing left today: say so, then tomorrow.
                freeLine
            }
            ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                if index == firstTomorrow {
                    Text("Tomorrow")
                        .eText(.caption)
                        .foregroundStyle(DSE.Palette.textTertiary)
                        .frame(height: 16, alignment: .bottomLeading)
                }
                TimeLineRow(
                    time: NextEventRow.timeText(NextEvents.time(of: event, now: now)),
                    title: event.title,
                    isCurrent: index == current,
                    help: String(localized: "Open in Calendar")
                ) {
                    onOpen(event)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: NextEventRow.accessibilityText(
                    time: NextEvents.time(of: event, now: now),
                    title: event.title,
                    isTomorrow: NextEvents.day(of: event, now: now) == .tomorrow
                )))
            }
        }
    }
}

/// «ДАЛЕЕ» as a micro-label; E shows no date (VISUAL-E §2.6).
private struct NextEventsHeading: View {
    let now: Date

    var body: some View {
        MicroLabel(String(localized: "Next"))
    }
}

/// "Next" beside the compact one-row player: up to two lines and no card,
/// so the island stays one row high. There is no "Tomorrow" heading here,
/// so tomorrow's events say it in their line.
struct NextEventLines: View {
    let state: NextEvents.State
    let now: Date
    /// "Next" and the date on top, when nothing plays in the compact island.
    var showsHeading = false
    var onAllowAccess: () -> Void = {}
    /// Set while reminders can be offered (see `NextEvents.offersReminders`).
    var onAllowReminders: (() -> Void)? = nil
    var onOpen: (EventModel) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showsHeading {
                NextEventsHeading(now: now)
                    .padding(.bottom, 4)
            }
            switch state {
            case .noAccess:
                if !showsHeading {
                    Text("Next")
                        .font(DS.Typeface.caption)
                        .foregroundStyle(DS.Palette.textTertiary)
                }
                Button(String(localized: "Allow Access"), action: onAllowAccess)
                    .buttonStyle(DSButtonStyle(kind: .secondary, height: 24))
            case .free:
                Label(String(localized: "Free for the rest of the day"), systemImage: "checkmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Palette.textSecondary)
                    .lineLimit(1)
            case .events(let events):
                ForEach(events, id: \.id) { event in
                    NextEventRow(
                        event: event,
                        time: NextEvents.time(of: event, now: now),
                        isTomorrow: NextEvents.day(of: event, now: now) == .tomorrow
                    ) {
                        onOpen(event)
                    }
                }
            }
            if let onAllowReminders {
                RemindersOfferRow(onAllow: onAllowReminders)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// A line beside the compact player. E: a 6 pt dot (lit while the event is
/// on) instead of the calendar's colour, and no fill under the pointer.
private struct NextEventRow: View {
    let event: EventModel
    let time: NextEvents.Time
    /// Says "Tomorrow" before the title, where no heading does.
    var isTomorrow = false
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if time == .now {
                    LitDot()
                } else {
                    Circle()
                        .fill(DSE.Palette.textTertiary)
                        .frame(width: DSE.Size.dot, height: DSE.Size.dot)
                }
                Text(timeText)
                    .eText(.bodyTabular)
                    .foregroundStyle(time == .now || isHovering ? DSE.Palette.text : DSE.Palette.textSecondary)
                    .lineLimit(1)
                    .frame(width: Self.timeColumnWidth, alignment: .leading)
                if isTomorrow {
                    Text("Tomorrow")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.Palette.textTertiary)
                        .lineLimit(1)
                        .fixedSize()
                }
                Text(event.title)
                    .font(DS.Typeface.body)
                    .foregroundStyle(DS.Palette.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .frame(height: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressDimStyle())
        .onHover { hovering in withAnimation(DS.hover) { isHovering = hovering } }
        .help(String(localized: "Open in Calendar"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityText))
    }

    /// One width for every row, so the titles line up: "12:30 PM" needs
    /// more room than "12:30".
    static let timeColumnWidth: CGFloat = {
        let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? ""
        return format.contains("a") ? 62 : 40
    }()

    private var accessibilityText: String {
        Self.accessibilityText(time: time, title: event.title, isTomorrow: isTomorrow)
    }

    /// «Завтра, 10:00, Title»: the spoken row, with the day the line of
    /// time shows only as a heading.
    static func accessibilityText(time: NextEvents.Time, title: String, isTomorrow: Bool) -> String {
        ((isTomorrow ? [String(localized: "Tomorrow")] : []) + [timeText(time), title]).joined(separator: ", ")
    }

    private var timeText: String { Self.timeText(time) }

    static func timeText(_ time: NextEvents.Time) -> String {
        switch time {
        case .now: return String(localized: "Now")
        case .allDay: return String(localized: "All day")
        case .at(let date): return date.formatted(date: .omitted, time: .shortened)
        }
    }
}

/// "Reminders too · Allow Access": one line in "Next" until the reminders
/// permission is answered. A click asks macOS; nothing asks on its own.
struct RemindersOfferRow: View {
    let onAllow: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(String(localized: "Reminders too"))
                .eText(.body)
                .foregroundStyle(DSE.Palette.textSecondary)
                .lineLimit(1)
            Button(String(localized: "Allow Access"), action: onAllow)
                .buttonStyle(SecondaryKeyStyle(height: 22))
                .fixedSize()
        }
    }
}
