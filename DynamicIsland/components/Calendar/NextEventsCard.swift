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
            switch style {
            case .card:
                NextEventsCardContent(state: state, now: context.date, onAllowAccess: allowAccess, onOpen: open)
            case .lines:
                NextEventLines(state: state, now: context.date, onAllowAccess: allowAccess, onOpen: open)
            case .headedLines:
                NextEventLines(state: state, now: context.date, showsHeading: true, onAllowAccess: allowAccess, onOpen: open)
                    .padding(.horizontal, 6)
            }
        }
        .onAppear { refresh() }
        .onChange(of: vm.notchState) { _, state in
            if state == .open { refresh() }
        }
    }

    private func refresh() {
        Task { await calendarManager.updateUpcomingEvents() }
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
                await calendarManager.updateUpcomingEvents(force: true)
            }
        default:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

/// The card drawn from plain values.
struct NextEventsCardContent: View {
    let state: NextEvents.State
    let now: Date
    var onAllowAccess: () -> Void = {}
    var onOpen: (EventModel) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NextEventsHeading(now: now)

            switch state {
            case .noAccess:
                Text("To see your next events, allow access to the calendar.")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(String(localized: "Allow Access"), action: onAllowAccess)
                    .buttonStyle(DSButtonStyle(kind: .secondary, height: 26))
            case .free:
                freeLine
            case .events(let events):
                eventRows(events)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous)
                .fill(DS.Palette.surface)
        )
    }

    private var freeLine: some View {
        Label(String(localized: "Free for the rest of the day"), systemImage: "checkmark.circle")
            .font(.system(size: 12))
            .foregroundStyle(DS.Palette.textSecondary)
    }

    @ViewBuilder
    private func eventRows(_ events: [EventModel]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            let firstTomorrow = events.firstIndex { NextEvents.day(of: $0, now: now) == .tomorrow }
            if firstTomorrow == 0 {
                // Nothing left today: say so, then tomorrow.
                freeLine
            }
            ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                if index == firstTomorrow {
                    Text("Tomorrow")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.Palette.textTertiary)
                        .padding(.top, index == 0 ? 2 : 4)
                }
                NextEventRow(event: event, time: NextEvents.time(of: event, now: now)) {
                    onOpen(event)
                }
            }
        }
    }
}

/// "Next" and today's date.
private struct NextEventsHeading: View {
    let now: Date

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Next")
                .font(DS.Typeface.bodyEmphasis)
                .foregroundStyle(DS.Palette.text)
            Spacer(minLength: 0)
            Text(now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                .font(DS.Typeface.caption)
                .foregroundStyle(DS.Palette.textTertiary)
                .lineLimit(1)
        }
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

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
                Circle()
                    .fill(Color(nsColor: event.calendar.color))
                    .frame(width: 7, height: 7)
                Text(timeText)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(time == .now ? DS.Palette.accent : DS.Palette.textSecondary)
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
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                    .fill(isHovering ? DS.Palette.hoverFill : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        ((isTomorrow ? [String(localized: "Tomorrow")] : []) + [timeText, event.title]).joined(separator: ", ")
    }

    private var timeText: String {
        switch time {
        case .now: return String(localized: "Now")
        case .allDay: return String(localized: "All day")
        case .at(let date): return date.formatted(date: .omitted, time: .shortened)
        }
    }
}
