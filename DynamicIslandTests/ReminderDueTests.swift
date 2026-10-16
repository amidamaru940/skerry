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

@testable import Atoll
import AppKit
import SwiftUI
import XCTest

/// A reminder for tomorrow made in the Reminders app did not show in "Next":
/// its due date came without a calendar, so `DateComponents.date` was nil and
/// the reminder was dropped.
final class ReminderDueTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
        return calendar
    }

    func testADueDateWithoutACalendarIsStillADate() {
        let components = DateComponents(year: 2026, month: 10, day: 16, hour: 10)
        XCTAssertNil(components.date, "this is how EventKit often hands it over")

        let due = ReminderDue.date(of: components, calendar: calendar)

        XCTAssertEqual(due, calendar.date(from: components))
    }

    func testADateOnlyReminderIsDueAtTheStartOfItsDay() {
        let components = DateComponents(year: 2026, month: 10, day: 16)

        let due = ReminderDue.date(of: components, calendar: calendar)

        XCTAssertEqual(due, calendar.startOfDay(for: calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 12))!))
    }

    func testComponentsThatCarryTheirCalendarKeepIt() {
        var components = DateComponents(year: 2026, month: 10, day: 16, hour: 10)
        components.calendar = calendar
        components.timeZone = calendar.timeZone

        XCTAssertEqual(ReminderDue.date(of: components, calendar: Calendar(identifier: .gregorian)), components.date)
    }

    // MARK: Asking for reminders

    /// Reminders are a permission of their own, and Skerry never asked for
    /// it: with calendar access granted, "Next" stayed "Free for the rest of
    /// the day" over a reminder due tomorrow.
    func testNextOffersRemindersWhileNobodyHasAnswered() {
        XCTAssertTrue(NextEvents.offersReminders(calendarAuthorized: true, remindersUndecided: true, shownEvents: 0, limit: 2))
        XCTAssertFalse(NextEvents.offersReminders(calendarAuthorized: true, remindersUndecided: false, shownEvents: 0, limit: 2), "answered either way: no more asking")
        XCTAssertFalse(NextEvents.offersReminders(calendarAuthorized: false, remindersUndecided: true, shownEvents: 0, limit: 2), "calendar access comes first")
        XCTAssertFalse(NextEvents.offersReminders(calendarAuthorized: true, remindersUndecided: true, shownEvents: 2, limit: 2), "no line free for it")
    }

    @MainActor
    func testTheOfferFitsBesideTheCompactPlayer() {
        let lines = NextEventLines(state: .free, now: Date(), onAllowReminders: {})
            .frame(width: CompactPlayerRowContent.nextWidth)
        let host = NSHostingView(rootView: lines)
        XCTAssertLessThanOrEqual(host.fittingSize.height, 56, "the one-row player is 56 points tall")
    }
}
