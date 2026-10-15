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
import Defaults
import XCTest

final class ClosedIndicatorTests: XCTestCase {
    private let defaultOrder = ClosedIndicator.defaultOrder

    func testDefaultOrderIsScreenshotClipboardPauseMusicTimerThenTheRest() {
        // The colour flash (15.10) sits with the screenshot flash, before music.
        XCTAssertEqual(Array(defaultOrder.prefix(5)), [.screenshot, .colorPicked, .clipboardPaused, .music, .timer])
        XCTAssertEqual(Array(defaultOrder.dropFirst(5)),
                       [.reminder, .recording, .download, .localSend, .focus, .privacy, .extensionActivity, .shelf, .keepAwake])
        XCTAssertEqual(Set(defaultOrder), Set(ClosedIndicator.allCases))
        XCTAssertEqual(Defaults.Keys.closedIndicatorPriority.defaultValue, defaultOrder)
        XCTAssertEqual(Defaults.Keys.closedMusicStyle.defaultValue, .artworkAndVisualizer)
    }

    func testTheFirstActiveIndicatorInTheListWins() {
        let active: Set<ClosedIndicator> = [.shelf, .download, .timer]
        XCTAssertEqual(ClosedIndicatorResolver.winner(active: active, order: defaultOrder), .timer)
        XCTAssertNil(ClosedIndicatorResolver.winner(active: [], order: defaultOrder))
    }

    func testChangingTheOrderChangesTheWinner() {
        let active: Set<ClosedIndicator> = [.shelf, .download, .timer]
        let shelfFirst = ClosedIndicatorResolver.move(.shelf, onto: .screenshot, in: defaultOrder)
        XCTAssertEqual(ClosedIndicatorResolver.winner(active: active, order: shelfFirst), .shelf)

        let downloadAboveTimer = ClosedIndicatorResolver.move(.download, onto: .timer, in: defaultOrder)
        XCTAssertEqual(ClosedIndicatorResolver.winner(active: active, order: downloadAboveTimer), .download)
    }

    func testByDefaultAScreenshotPushesMusicAsideForAMoment() {
        let active: Set<ClosedIndicator> = [.music, .screenshot]
        XCTAssertEqual(ClosedIndicatorResolver.winner(active: active, order: defaultOrder), .screenshot)

        let musicFirst = ClosedIndicatorResolver.move(.music, onto: .screenshot, in: defaultOrder)
        XCTAssertEqual(ClosedIndicatorResolver.winner(active: active, order: musicFirst), .music)
    }

    func testIndicatorsThatPairWithMusicBecomeItsBadgeInListOrder() {
        let active: Set<ClosedIndicator> = [.music, .clipboardPaused, .timer, .shelf]
        // Clipboard pause is above music, but it rides along as the badge.
        XCTAssertEqual(ClosedIndicatorResolver.winner(active: active, order: defaultOrder), .music)
        XCTAssertEqual(ClosedIndicatorResolver.musicBadge(active: active, order: defaultOrder), .clipboardPaused)

        let timerFirst = ClosedIndicatorResolver.move(.timer, onto: .screenshot, in: defaultOrder)
        XCTAssertEqual(ClosedIndicatorResolver.winner(active: active, order: timerFirst), .music)
        XCTAssertEqual(ClosedIndicatorResolver.musicBadge(active: active, order: timerFirst), .timer)

        XCTAssertNil(ClosedIndicatorResolver.musicBadge(active: [.music, .download, .privacy], order: defaultOrder))
    }

    func testIndicatorsThatCannotPairReplaceMusicOnlyWhenAboveIt() {
        let active: Set<ClosedIndicator> = [.music, .download, .privacy]
        XCTAssertEqual(ClosedIndicatorResolver.winner(active: active, order: defaultOrder), .music)

        let downloadFirst = ClosedIndicatorResolver.move(.download, onto: .screenshot, in: defaultOrder)
        XCTAssertEqual(ClosedIndicatorResolver.winner(active: active, order: downloadFirst), .download)
    }

    func testWithoutMusicEveryIndicatorCompetesByTheList() {
        XCTAssertEqual(ClosedIndicatorResolver.winner(active: [.timer, .clipboardPaused], order: defaultOrder), .clipboardPaused)
        XCTAssertEqual(ClosedIndicatorResolver.winner(active: [.shelf, .focus], order: defaultOrder), .focus)
    }

    /// Below the system HUDs, the default list keeps upstream's closed-island
    /// order (with the fork's screenshot flash and clipboard pause).
    func testTheDefaultListKeepsUpstreamOrderWithoutMusic() {
        let chain: [ClosedIndicator] = [.screenshot, .clipboardPaused, .timer, .reminder, .recording,
                                        .download, .localSend, .focus, .privacy, .extensionActivity, .shelf]
        for (index, higher) in chain.enumerated() {
            for lower in chain.dropFirst(index + 1) {
                XCTAssertEqual(ClosedIndicatorResolver.winner(active: [higher, lower], order: defaultOrder), higher,
                               "\(higher) should beat \(lower)")
            }
        }
    }

    func testTheDefaultListKeepsUpstreamOrderWithMusic() {
        // Upstream showed music over every indicator except the screenshot
        // flash, and picked its badge in this order. The colour flash is the
        // fork's own (15.10) and, like the screenshot flash, answers a click,
        // so it shows over music too (MediumAuditTests).
        for other in ClosedIndicator.allCases where other != .music && other != .screenshot && other != .colorPicked {
            XCTAssertEqual(ClosedIndicatorResolver.winner(active: [.music, other], order: defaultOrder), .music,
                           "music should beat \(other)")
        }
        let badges: [ClosedIndicator] = [.clipboardPaused, .timer, .reminder, .recording, .focus, .extensionActivity, .shelf]
        for (index, higher) in badges.enumerated() {
            for lower in badges.dropFirst(index + 1) {
                XCTAssertEqual(ClosedIndicatorResolver.musicBadge(active: [.music, higher, lower], order: defaultOrder), higher)
            }
        }
    }

    func testOnlyIndicatorsWithABadgeViewPairWithMusic() {
        XCTAssertEqual(Set(ClosedIndicator.allCases.filter(\.pairsWithMusic)),
                       [.clipboardPaused, .timer, .reminder, .recording, .focus, .extensionActivity, .shelf, .keepAwake])
    }

    func testBadgeLookupStopsAtTheFirstMatchAndSkipsIndicatorsWithoutABadge() {
        var asked: [ClosedIndicator] = []
        let badge = ClosedIndicatorResolver.firstMusicBadge(order: defaultOrder) { indicator -> String? in
            asked.append(indicator)
            return indicator == .reminder ? "reminder" : nil
        }
        XCTAssertEqual(badge, "reminder")
        XCTAssertEqual(asked, [.clipboardPaused, .timer, .reminder])
    }

    func testNormalizedOrderDropsDuplicatesAndAppendsNewIndicators() {
        let order = ClosedIndicatorResolver.normalizedOrder([.timer, .music, .timer])
        XCTAssertEqual(Array(order.prefix(2)), [.timer, .music])
        XCTAssertEqual(order.count, ClosedIndicator.allCases.count)
        XCTAssertEqual(Array(order.dropFirst(2)), defaultOrder.filter { $0 != .timer && $0 != .music })
    }

    func testMoveDropsARowOntoAnother() {
        let order: [ClosedIndicator] = [.screenshot, .clipboardPaused, .music, .timer]
        XCTAssertEqual(Array(ClosedIndicatorResolver.move(.timer, onto: .screenshot, in: order).prefix(4)),
                       [.timer, .screenshot, .clipboardPaused, .music])
        XCTAssertEqual(Array(ClosedIndicatorResolver.move(.screenshot, onto: .music, in: order).prefix(4)),
                       [.clipboardPaused, .music, .screenshot, .timer])
        XCTAssertEqual(Array(ClosedIndicatorResolver.move(.music, onto: .music, in: order).prefix(4)), order)
    }

    func testMusicStyles() {
        XCTAssertEqual(ClosedMusicStyle.allCases, [.artworkAndVisualizer, .artworkOnly, .visualizerOnly, .scrollingTitle, .nothing])
        XCTAssertEqual(ClosedMusicStyle.allCases.filter(\.showsArtwork), [.artworkAndVisualizer, .artworkOnly, .scrollingTitle])
        XCTAssertEqual(ClosedMusicStyle.allCases.filter(\.showsVisualizer), [.artworkAndVisualizer, .visualizerOnly])
        XCTAssertEqual(ClosedMusicStyle.allCases.filter { !$0.showsMusic }, [.nothing])
    }

    func testNothingStyleKeepsMusicOffTheClosedIsland() {
        XCTAssertTrue(ClosedMusicStyle.closedMusicContentEnabled(standardMediaControls: true, style: .artworkOnly))
        XCTAssertFalse(ClosedMusicStyle.closedMusicContentEnabled(standardMediaControls: true, style: .nothing))
        XCTAssertFalse(ClosedMusicStyle.closedMusicContentEnabled(standardMediaControls: false, style: .artworkAndVisualizer))

        // With music off the closed island, music is not eligible, so other
        // indicators (recording included) show on their own.
        let eligible = isClosedMusicPairingEligible(
            notchState: .closed, hasActiveMusicSnapshot: true, musicLiveActivityEnabled: true,
            closedMusicContentEnabled: ClosedMusicStyle.closedMusicContentEnabled(standardMediaControls: true, style: .nothing),
            hideOnClosed: false, isLocked: false, isDeferredAfterUnlock: false
        )
        XCTAssertFalse(eligible)
        XCTAssertEqual(ClosedIndicatorResolver.winner(active: [.recording], order: defaultOrder), .recording)
    }
}

/// Uses the real settings store; every key touched is restored.
final class ClosedIndicatorPersistenceTests: XCTestCase {
    private var savedPriority: [ClosedIndicator] = []
    private var savedStyle: ClosedMusicStyle = .artworkAndVisualizer

    override func setUp() {
        super.setUp()
        savedPriority = Defaults[.closedIndicatorPriority]
        savedStyle = Defaults[.closedMusicStyle]
    }

    override func tearDown() {
        Defaults[.closedIndicatorPriority] = savedPriority
        Defaults[.closedMusicStyle] = savedStyle
        super.tearDown()
    }

    func testPriorityAndMusicStyleAreSavedAndRestored() {
        let order = ClosedIndicatorResolver.move(.shelf, onto: .screenshot, in: ClosedIndicator.defaultOrder)
        Defaults[.closedIndicatorPriority] = order
        Defaults[.closedMusicStyle] = .scrollingTitle

        XCTAssertEqual(Defaults[.closedIndicatorPriority], order)
        XCTAssertEqual(Defaults[.closedMusicStyle], .scrollingTitle)
        XCTAssertEqual(ClosedIndicatorResolver.winner(active: [.timer, .shelf], order: Defaults[.closedIndicatorPriority]), .shelf)

        Defaults.reset(.closedIndicatorPriority, .closedMusicStyle)
        XCTAssertEqual(Defaults[.closedIndicatorPriority], ClosedIndicator.defaultOrder)
        XCTAssertEqual(Defaults[.closedMusicStyle], .artworkAndVisualizer)
    }
}
