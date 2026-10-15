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

/// Step D3: "Next" instead of the month strip, the calm player, "nothing
/// playing". Event titles here are made up.
final class NowTabTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
        return calendar
    }()

    /// 15 Oct 2026, 13:00 Moscow time.
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 13))! }

    private func at(day: Int = 15, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func event(_ title: String, _ start: Date, _ end: Date, allDay: Bool = false, type: EventType = .event(.accepted)) -> EventModel {
        EventModel(
            id: title, start: start, end: end, title: title, location: nil, notes: nil, url: nil,
            isAllDay: allDay, type: type,
            calendar: CalendarModel(accountName: "Local", id: "local", title: "Home", color: .systemBlue, isSubscribed: false, isReminder: false),
            participants: [], timeZone: nil, hasRecurrenceRules: false, priority: nil, conferenceURL: nil
        )
    }

    // MARK: Next

    func testNextShowsWhatIsStillToComeTodayThenTomorrow() {
        let events = [
            event("Breakfast", at(8), at(9)),                       // ended
            event("Team call", at(14), at(15)),
            event("Workout", at(16, 30), at(18)),
            event("Meeting", at(day: 16, 10), at(day: 16, 11)),      // tomorrow
            event("Trip", at(day: 17, 9), at(day: 17, 12)),          // the day after: not shown
            event("Lunch", at(12, 30), at(13, 30)),                  // in progress
        ]
        let next = NextEvents.pick(events, now: now, hideAllDay: false, calendar: calendar)
        XCTAssertEqual(next.map(\.title), ["Lunch", "Team call", "Workout"], "three at most, earliest first")
        let all = NextEvents.pick(events, now: now, hideAllDay: false, calendar: calendar, limit: 10)
        XCTAssertEqual(all.map(\.title), ["Lunch", "Team call", "Workout", "Meeting"])
    }

    func testAllDayEventsLeadTheirDayUnlessHidden() {
        let holiday = event("Holiday", at(0), at(day: 16, 0), allDay: true)
        let call = event("Team call", at(14), at(15))
        XCTAssertEqual(NextEvents.pick([call, holiday], now: now, hideAllDay: false, calendar: calendar).map(\.title), ["Holiday", "Team call"])
        XCTAssertEqual(NextEvents.pick([call, holiday], now: now, hideAllDay: true, calendar: calendar).map(\.title), ["Team call"])
    }

    func testCompletedRemindersAreLeftOut() {
        let done = event("Pay rent", at(15), at(15), type: .reminder(completed: true))
        let open = event("Call back", at(16), at(16), type: .reminder(completed: false))
        // A reminder at its own minute counts until that minute ends.
        let openEnd = event("Buy milk", at(17), at(17, 1), type: .reminder(completed: false))
        XCTAssertEqual(NextEvents.pick([done, open, openEnd], now: now, hideAllDay: false, calendar: calendar).map(\.title), ["Call back", "Buy milk"])
    }

    func testTheCardStates() {
        let call = event("Team call", at(14), at(15))
        XCTAssertEqual(NextEvents.state(authorized: false, events: [call], now: now, hideAllDay: false, calendar: calendar), .noAccess)
        XCTAssertEqual(NextEvents.state(authorized: true, events: [], now: now, hideAllDay: false, calendar: calendar), .free)
        XCTAssertEqual(NextEvents.state(authorized: true, events: [call], now: now, hideAllDay: false, calendar: calendar), .events([call]))
        XCTAssertEqual(NextEvents.state(authorized: true, events: [call, event("B", at(15), at(16))], now: now,
                                        hideAllDay: false, calendar: calendar, limit: 1), .events([call]))
    }

    func testEachRowSaysNowAllDayOrItsTime() {
        XCTAssertEqual(NextEvents.time(of: event("Lunch", at(12, 30), at(13, 30)), now: now), .now)
        XCTAssertEqual(NextEvents.time(of: event("Holiday", at(0), at(day: 16, 0), allDay: true), now: now), .allDay)
        XCTAssertEqual(NextEvents.time(of: event("Call", at(14), at(15)), now: now), .at(at(14)))
        XCTAssertEqual(NextEvents.day(of: event("Call", at(14), at(15)), now: now, calendar: calendar), .today)
        XCTAssertEqual(NextEvents.day(of: event("Meeting", at(day: 16, 10), at(day: 16, 11)), now: now, calendar: calendar), .tomorrow)
        // Started yesterday, still running: today.
        XCTAssertEqual(NextEvents.day(of: event("Night shift", at(day: 14, 22), at(14)), now: now, calendar: calendar), .today)
    }

    // MARK: Layout of the tab

    func testTheTabLayout() {
        XCTAssertEqual(NowTabLayout.resolve(playerShown: true, isPlaying: true, playerIdle: false, calendarOn: true, compact: false), .player(next: true))
        XCTAssertEqual(NowTabLayout.resolve(playerShown: true, isPlaying: false, playerIdle: false, calendarOn: true, compact: false), .player(next: true),
                       "just paused: still the player")
        XCTAssertEqual(NowTabLayout.resolve(playerShown: true, isPlaying: false, playerIdle: true, calendarOn: true, compact: false), .idle)
        XCTAssertEqual(NowTabLayout.resolve(playerShown: true, isPlaying: false, playerIdle: true, calendarOn: false, compact: false), .player(next: false),
                       "without the calendar the paused player stays")
        XCTAssertEqual(NowTabLayout.resolve(playerShown: false, isPlaying: false, playerIdle: true, calendarOn: true, compact: false), .nextOnly)
        XCTAssertEqual(NowTabLayout.resolve(playerShown: false, isPlaying: false, playerIdle: true, calendarOn: false, compact: false), .nothing)
        XCTAssertEqual(NowTabLayout.resolve(playerShown: true, isPlaying: true, playerIdle: false, calendarOn: true, compact: true), .player(next: false),
                       "compact: the player has the whole width")
    }

    // MARK: Player buttons

    func testTheTransportStaysAndTheRestGoesToTheSides() {
        let split = PlayerControlsLayout.split(MusicControlButton.defaultLayout, addingOutput: true, addingLyrics: true)
        XCTAssertEqual(split.transport, [.trackBackward, .playPause, .trackForward])
        XCTAssertEqual(split.leading, [.shuffle, .repeatMode])
        XCTAssertEqual(split.trailing, [.mediaOutput, .lyrics])
    }

    func testTheUsersSlotsAreKept() {
        let custom: [MusicControlButton] = [.likeTrack, .seekBackward, .playPause, .seekForward, .airPlay]
        let split = PlayerControlsLayout.split(custom, addingOutput: true, addingLyrics: false)
        XCTAssertEqual(split.transport, [.seekBackward, .playPause, .seekForward])
        XCTAssertEqual(split.leading, [.likeTrack])
        XCTAssertEqual(split.trailing, [.airPlay], "AirPlay already picks the output")

        let minimal = PlayerControlsLayout.split(MusicControlButton.minimalLayout)
        XCTAssertEqual(minimal, .init(leading: [], transport: [.trackBackward, .playPause, .trackForward], trailing: []))
        XCTAssertEqual(PlayerControlsLayout.split([.shuffle, .none]).transport, [.trackBackward, .playPause, .trackForward],
                       "never a player without play")
    }

    // MARK: Drawing

    /// Draws the new pieces; with SKERRY_SNAPSHOT_DIR set (TEST_RUNNER_ prefix
    /// for xcodebuild) the pictures are saved there for a look.
    @MainActor
    func testTheNewPiecesDraw() throws {
        let call = event("Team call", at(14), at(15))
        let workout = event("Workout", at(16, 30), at(18))
        let meeting = event("Meeting", at(day: 16, 10), at(day: 16, 11))
        let pieces: [(String, AnyView, CGSize)] = [
            ("next-events", AnyView(NextEventsCardContent(state: .events([call, workout, meeting]), now: now)), CGSize(width: 230, height: 132)),
            ("next-tomorrow", AnyView(NextEventsCardContent(state: .events([meeting]), now: now)), CGSize(width: 230, height: 132)),
            ("next-free", AnyView(NextEventsCardContent(state: .free, now: now)), CGSize(width: 230, height: 132)),
            ("next-no-access", AnyView(NextEventsCardContent(state: .noAccess, now: now)), CGSize(width: 600, height: 92)),
            ("idle-strip", AnyView(IdlePlayerStripContent(artwork: NSImage(systemSymbolName: "music.note", accessibilityDescription: nil), title: "Nightcall", artist: "Kavinsky")), CGSize(width: 600, height: 36)),
            ("idle-strip-empty", AnyView(IdlePlayerStripContent(artwork: nil, title: nil, artist: "")), CGSize(width: 600, height: 36)),
        ]
        let folder = ProcessInfo.processInfo.environment["SKERRY_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
        for (name, view, size) in pieces {
            let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height).padding(8).background(Color.black).environment(\.colorScheme, .dark))
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.nsImage, name)
            XCTAssertEqual(image.size.width, size.width + 16, accuracy: 1, name)
            if let folder, let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try png.write(to: folder.appendingPathComponent("\(name).png"))
            }
        }
    }

    // MARK: Compact (owner's choice, 15.10): "Next" beside the one-row player

    @MainActor
    func testCompactKeepsTheNextTwoEventsInTheSameRow() throws {
        let events = [
            event("Team call", at(14), at(15)),
            event("Workout", at(16, 30), at(18)),
            event("Meeting", at(day: 16, 10), at(day: 16, 11)),
        ]
        let state = NextEvents.state(authorized: true, events: events, now: now, hideAllDay: false, calendar: calendar, limit: NextEvents.compactLimit)
        XCTAssertEqual(state, .events(Array(events.prefix(2))), "two lines fit the one row")

        let folder = ProcessInfo.processInfo.environment["SKERRY_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
        let cases: [(String, NextEvents.State)] = [
            ("compact-next-events", state),
            ("compact-next-tomorrow", .events([events[2]])),
            ("compact-next-no-access", .noAccess),
            ("compact-next-free", .free),
        ]
        for (name, lines) in cases {
            let row = CompactPlayerRowContent(
                artwork: NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)!,
                title: "Nightcall", artist: "Kavinsky", progress: 0.34, isPlaying: true,
                next: AnyView(NextEventLines(state: lines, now: now))
            )
            let renderer = ImageRenderer(content: row.frame(width: 640).padding(8).background(Color.black).environment(\.colorScheme, .dark))
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.nsImage, name)
            XCTAssertEqual(image.size.height, 72, accuracy: 1, "\(name): the island stays one row high")
            if let folder, let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try png.write(to: folder.appendingPathComponent("\(name).png"))
            }
        }
    }

    // MARK: No music: "Next" alone (owner's report, 15.10)

    func testNextAloneNeverWaitsForTheDeferral() {
        XCTAssertTrue(NowTabLayout.nextOnly.showsNext(deferralDone: false),
                      "alone on the tab it is what has to appear; gated, the tab stayed empty")
        XCTAssertFalse(NowTabLayout.player(next: true).showsNext(deferralDone: false), "beside the player it waits")
        XCTAssertTrue(NowTabLayout.player(next: true).showsNext(deferralDone: true))
        XCTAssertFalse(NowTabLayout.player(next: false).showsNext(deferralDone: true))
        XCTAssertFalse(NowTabLayout.idle.showsNext(deferralDone: false), "the idle strip appears first")
        XCTAssertTrue(NowTabLayout.idle.showsNext(deferralDone: true))
        XCTAssertFalse(NowTabLayout.nothing.showsNext(deferralDone: true))
    }

    @MainActor
    func testNextAloneFitsTheCompactIsland() throws {
        let events = [event("Team call", at(14), at(15)), event("Meeting", at(day: 16, 10), at(day: 16, 11))]
        let state = NextEvents.state(authorized: true, events: events, now: now, hideAllDay: false, calendar: calendar, limit: NextEvents.compactLimit)
        let folder = ProcessInfo.processInfo.environment["SKERRY_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
        for (name, lines) in [("compact-next-alone", state), ("compact-next-alone-no-access", NextEvents.State.noAccess)] {
            let view = NextEventLines(state: lines, now: now, showsHeading: true).fixedSize(horizontal: false, vertical: true)
            let renderer = ImageRenderer(content: view.frame(width: 700).background(Color.black).environment(\.colorScheme, .dark))
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.nsImage, name)
            // 140 pt island, less the header (the 38 pt notch) and the tab's 8 pt padding above and below.
            XCTAssertLessThanOrEqual(image.size.height, compactHomeOpenHeight - 38 - 16, "\(name): fits the lower island without clipping")
            if let folder, let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try png.write(to: folder.appendingPathComponent("\(name).png"))
            }
        }
    }
}
