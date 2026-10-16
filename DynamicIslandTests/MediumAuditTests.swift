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
import Defaults
import SwiftUI
import XCTest

/// The audit's medium items, done after the live check (15.10): Markup one
/// after another, the picked colour as a flash, the Usage tab. Nothing here
/// opens a window or touches the network.
final class MediumAuditTests: XCTestCase {

    // MARK: Markup

    @MainActor
    func testMarkupOpensTheScreenshotsOneAfterAnother() {
        var opened: [String] = []
        let queue = MarkupQueue { url, _ in
            opened.append(url.lastPathComponent)
            return url.pathExtension == "png" ? NSObject() : nil
        }
        let urls = ["a.png", "clip.mov", "b.png", "c.png"].map { URL(fileURLWithPath: "/tmp/\($0)") }

        XCTAssertTrue(queue.start(urls))
        XCTAssertEqual(opened, ["a.png"], "one at a time")
        queue.finished(saved: true)
        XCTAssertEqual(opened, ["a.png", "clip.mov", "b.png"], "a video Markup cannot take is skipped")
        queue.finished(saved: false)
        XCTAssertTrue(queue.pending.isEmpty, "cancelling stops the rest")
        queue.finished(saved: true)
        XCTAssertEqual(opened.count, 3, "nothing opens after the queue stopped")

        XCTAssertTrue(queue.start([urls[3]]), "a new Markup starts over")
        XCTAssertEqual(opened.last, "c.png")
        XCTAssertFalse(MarkupQueue { _, _ in nil }.start([urls[1]]), "nothing Markup can take: the caller opens Preview")
    }

    // MARK: Colour picker

    @MainActor
    func testAPickFlashesTheColourInsteadOfOpeningThePanel() {
        let fromMenu = ColorPickerManager.afterPick(startedFromPanel: false)
        XCTAssertTrue(fromMenu.flashes)
        XCTAssertFalse(fromMenu.reopensPanel, "no window after a pick")
        let fromPanel = ColorPickerManager.afterPick(startedFromPanel: true)
        XCTAssertTrue(fromPanel.flashes, "every pick is confirmed on the island")
        XCTAssertTrue(fromPanel.reopensPanel, "the panel closes for a pick from its own button, so it comes back")
        XCTAssertFalse(fromPanel.panelTakesFocus, "but the app the colour is for keeps the focus, so ⌘V pastes there")

        let flash = ColorPickFlash()
        let color = PickedColor(nsColor: NSColor(srgbRed: 0.23, green: 0.48, blue: 1, alpha: 1), point: .zero)
        flash.show(color, for: 60)
        XCTAssertEqual(flash.color?.hexString, color.hexString)
        flash.clear()
        XCTAssertNil(flash.color)

        // The flash answers the user's own pick, so it comes before music.
        XCTAssertEqual(ClosedIndicatorResolver.winner(active: [.colorPicked, .music], order: ClosedIndicator.defaultOrder), .colorPicked)
        XCTAssertFalse(ClosedIndicator.colorPicked.pairsWithMusic)
    }

    @MainActor
    func testTheColourFlashKeepsTheNotchCentred() throws {
        let color = PickedColor(nsColor: NSColor(srgbRed: 0.23, green: 0.48, blue: 1, alpha: 1), point: .zero)
        let view = ColorPickedLiveActivityContent(color: color, notchWidth: 185, notchHeight: 32)
        let renderer = ImageRenderer(content: view.background(Color.black))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        let wings = 2 * (ColorPickedLiveActivityContent.wingWidth + 4)
        XCTAssertEqual(image.size.width, 185 + wings, accuracy: 1, "both wings as wide: the notch stays on the camera")
        XCTAssertEqual(image.size.height, 32, accuracy: 1)
        if let folder = ProcessInfo.processInfo.environment["SKERRY_SNAPSHOT_DIR"].map({ URL(fileURLWithPath: $0) }),
           let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try png.write(to: folder.appendingPathComponent("color-flash.png"))
        }
    }

    // MARK: Usage

    private struct FakeProvider: UsageProvider {
        let id: ProviderID
        let error: Error?
        func fetchSnapshot(now: Date) async throws -> UsageSnapshot {
            if let error { throw error }
            return UsageSnapshot(today: UsageTotals(inputTokens: 10, outputTokens: 5))
        }
    }

    func testAProviderNotOnThisMacIsNotReadOutAsAnError() {
        guard case .notFound = LLMUsageManager.result(for: UsageError.notFound("No ~/.codex/sessions")) else {
            return XCTFail("not on this Mac: a calm card with Hide")
        }
        guard case .failure(let reason) = LLMUsageManager.result(for: UsageError.notConfigured("Antigravity auth expired")) else {
            return XCTFail("a real failure keeps its reason")
        }
        XCTAssertEqual(reason, "Antigravity auth expired")
    }

    @MainActor
    func testRefreshingRecordsWhenItFinished() async throws {
        let saved = Defaults[.enableLLMUsageFeature]
        defer { Defaults[.enableLLMUsageFeature] = saved }
        Defaults[.enableLLMUsageFeature] = true

        let manager = LLMUsageManager(providers: [
            FakeProvider(id: .claude, error: nil),
            FakeProvider(id: .codex, error: UsageError.notFound("No ~/.codex/sessions")),
        ])
        XCTAssertNil(manager.lastUpdated)
        manager.refreshAll(force: true)
        for _ in 0..<200 where manager.isRefreshing {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertFalse(manager.isRefreshing)
        XCTAssertNotNil(manager.lastUpdated, "the bar can say when")
        guard case .success = manager.results[.claude] else { return XCTFail("Claude answered") }
        guard case .notFound = manager.results[.codex] else { return XCTFail("Codex is not on this Mac") }
    }

    @MainActor
    func testTheRefreshBarSaysWhenItLastUpdated() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertNil(UsageRefreshBar.updatedText(lastUpdated: nil, now: now), "nothing to say before the first refresh")
        XCTAssertEqual(UsageRefreshBar.updatedText(lastUpdated: now.addingTimeInterval(-20), now: now), String(localized: "Updated just now"))
        let fiveMinutes = UsageRefreshBar.updatedText(lastUpdated: now.addingTimeInterval(-300), now: now, locale: Locale(identifier: "en_US"))
        XCTAssertTrue(fiveMinutes?.contains("5") == true, fiveMinutes ?? "nil")
        XCTAssertEqual(tabOpenHeight(for: .llmUsage), usageTabOpenHeight, "the bar gets its own room")
        XCTAssertGreaterThan(usageTabOpenHeight, openNotchSize.height)
    }
}
