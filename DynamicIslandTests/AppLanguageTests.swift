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

/// The app language switch (pure parts; nothing is written to preferences)
/// and the Russian strings in the built app.
final class AppLanguageTests: XCTestCase {
    func testFollowsTheSystemByDefault() {
        XCTAssertEqual(AppLanguage.from(storedLanguages: nil), .system)
        XCTAssertEqual(AppLanguage.from(storedLanguages: []), .system)
        XCTAssertEqual(AppLanguage.allCases, [.system, .english, .russian])
    }

    func testChoosingALanguageStoresItAsTheAppsOwnLanguageList() {
        XCTAssertEqual(AppLanguage.storedLanguages(for: .russian), ["ru"])
        XCTAssertEqual(AppLanguage.storedLanguages(for: .english), ["en"])
        XCTAssertNil(AppLanguage.storedLanguages(for: .system))       // removes the override
        XCTAssertEqual(AppLanguage.from(storedLanguages: ["ru"]), .russian)
        XCTAssertEqual(AppLanguage.from(storedLanguages: ["ru-RU", "en"]), .russian)
        XCTAssertEqual(AppLanguage.from(storedLanguages: ["en-GB"]), .english)
        XCTAssertEqual(AppLanguage.from(storedLanguages: ["de"]), .system)
        for language in AppLanguage.allCases {
            XCTAssertEqual(AppLanguage.from(storedLanguages: AppLanguage.storedLanguages(for: language)), language)
        }
    }

    func testLanguagesAreNamedInThemselves() {
        XCTAssertEqual(AppLanguage.english.title, "English")
        XCTAssertEqual(AppLanguage.russian.title, "Русский")
    }

    /// The catalog compiles into the app: fork strings from several steps
    /// come out in Russian from the ru bundle and in English from en.
    func testTheBuiltAppHasRussianAndEnglish() throws {
        let ruPath = try XCTUnwrap(Bundle.main.path(forResource: "ru", ofType: "lproj"))
        let ru = try XCTUnwrap(Bundle(path: ruPath))
        let enPath = try XCTUnwrap(Bundle.main.path(forResource: "en", ofType: "lproj"))
        let en = try XCTUnwrap(Bundle(path: enPath))
        let samples = [
            "Open only by click": "Открывать только по клику",
            "Hide the island in full-screen apps": "Скрывать «островок» в полноэкранных приложениях",
            "Pinned": "Закреплённые",
            "No screenshots yet": "Скриншотов пока нет",
            "Turn on lyrics?": "Включить тексты песен?",
            "As in System": "Как в системе",
        ]
        for (key, russian) in samples {
            XCTAssertEqual(ru.localizedString(forKey: key, value: nil, table: "Localizable"), russian, key)
            XCTAssertEqual(en.localizedString(forKey: key, value: nil, table: "Localizable"), key, key)
        }
        // Plural forms: 1, 3, 5 screenshots.
        let format = ru.localizedString(forKey: "%lld screenshots", value: nil, table: "Localizable")
        let russianLocale = Locale(identifier: "ru_RU")
        XCTAssertEqual(String(format: format, locale: russianLocale, 1), "1 скриншот")
        XCTAssertEqual(String(format: format, locale: russianLocale, 3), "3 скриншота")
        XCTAssertEqual(String(format: format, locale: russianLocale, 5), "5 скриншотов")
    }

    func testPermissionRequestsAreInRussian() throws {
        let ruPath = try XCTUnwrap(Bundle.main.path(forResource: "ru", ofType: "lproj"))
        let ru = try XCTUnwrap(Bundle(path: ruPath))
        let text = ru.localizedString(forKey: "NSAppleEventsUsageDescription", value: nil, table: "InfoPlist")
        XCTAssertTrue(text.contains("AppleScript") && text.contains("управляет"), text)
    }
}
