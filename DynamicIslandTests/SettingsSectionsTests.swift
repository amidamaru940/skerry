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
import XCTest

/// Step D6: eight sections of Settings, search in Russian.
final class SettingsSectionsTests: XCTestCase {
    private let allPages = [
        "general", "layout", "liveActivities", "appearance", "lockScreen", "media", "devices", "extensions",
        "timer", "calendar", "hudAndOSD", "battery", "stats", "clipboard", "screenAssistant", "colorPicker",
        "downloads", "shelf", "screenshots", "shortcuts", "notes", "terminal", "about",
    ]

    func testEightSectionsHoldEveryPageOnce() {
        XCTAssertEqual(SettingsSectionLayout.allCases.count, 8)
        let pages = SettingsSectionLayout.allCases.flatMap(\.pageIDs)
        XCTAssertEqual(pages.count, Set(pages).count, "a page in two sections")
        XCTAssertEqual(Set(pages), Set(allPages), "every old tab has a home")
    }

    func testPagesLandWhereThePlanPutsThem() {
        XCTAssertEqual(SettingsSectionLayout.section(forPage: "layout"), .island)
        XCTAssertEqual(SettingsSectionLayout.section(forPage: "media"), .music)
        XCTAssertEqual(SettingsSectionLayout.section(forPage: "hudAndOSD"), .notifications)
        XCTAssertEqual(SettingsSectionLayout.section(forPage: "screenshots"), .productivity)
        XCTAssertEqual(SettingsSectionLayout.section(forPage: "terminal"), .tools)
        XCTAssertEqual(SettingsSectionLayout.section(forPage: "about"), .general)
        XCTAssertEqual(SettingsSectionLayout.allCases.last, .advanced, "the advanced bits come last")
        XCTAssertNil(SettingsSectionLayout.section(forPage: "nonsense"))
    }

    func testSearchUnderstandsRussian() throws {
        let ru = try XCTUnwrap(Bundle(path: try XCTUnwrap(Bundle.main.path(forResource: "ru", ofType: "lproj"))))
        XCTAssertTrue(SettingsSectionLayout.matches("Clipboard", query: "буфер", bundle: ru))
        XCTAssertTrue(SettingsSectionLayout.matches("Clipboard", query: "CLIP", bundle: ru), "English still works")
        XCTAssertTrue(SettingsSectionLayout.matches("Keep Awake", query: "засып", bundle: ru))
        XCTAssertFalse(SettingsSectionLayout.matches("Clipboard", query: "таймер", bundle: ru))
        XCTAssertFalse(SettingsSectionLayout.matches("Clipboard", query: "  ", bundle: ru))
    }
}
