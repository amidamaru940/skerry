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

/// Step D4: the Clipboard tab with the screenshots in it.
@MainActor
final class BufferTabTests: XCTestCase {
    // MARK: Segments and the batch strip

    func testSegmentsFollowWhatIsTurnedOn() {
        XCTAssertEqual(BufferSegment.available(clipboard: true, screenshots: true), [.all, .screenshots, .text, .links, .files])
        XCTAssertEqual(BufferSegment.available(clipboard: false, screenshots: true), [.screenshots])
        XCTAssertEqual(BufferSegment.available(clipboard: true, screenshots: false), [.all, .text, .links, .files])
        XCTAssertEqual(BufferSegment.available(clipboard: false, screenshots: false), [])
        XCTAssertEqual(BufferSegment.resolve(.text, available: [.screenshots]), .screenshots)
        XCTAssertEqual(BufferSegment.resolve(.links, available: [.all, .links]), .links)
        XCTAssertNil(BufferSegment.resolve(.all, available: []))
        XCTAssertNil(BufferSegment.screenshots.clipboardFilter)
        XCTAssertEqual(BufferSegment.files.clipboardFilter, .files)
    }

    func testTheLatestBatchSitsOnTopOfEverythingForADay() {
        let now = Date()
        XCTAssertTrue(BufferLayout.showsBatchStrip(segment: .all, lastAddedAt: now.addingTimeInterval(-3600), now: now))
        XCTAssertFalse(BufferLayout.showsBatchStrip(segment: .all, lastAddedAt: now.addingTimeInterval(-25 * 3600), now: now))
        XCTAssertFalse(BufferLayout.showsBatchStrip(segment: .screenshots, lastAddedAt: now, now: now), "the grid shows it already")
        XCTAssertFalse(BufferLayout.showsBatchStrip(segment: .text, lastAddedAt: now, now: now))
        XCTAssertFalse(BufferLayout.showsBatchStrip(segment: .all, lastAddedAt: nil, now: now))
    }

    func testThePasteButtonNamesTheAppOrSaysCopy() {
        let paste = BufferLayout.pasteTitle(count: 3, target: "Claude", canPaste: true)
        XCTAssertTrue(paste.contains("Claude") && paste.contains("3"), paste)
        let copy = BufferLayout.pasteTitle(count: 3, target: "Claude", canPaste: false)
        XCTAssertFalse(copy.contains("Claude"), "without Accessibility it can only copy")
        XCTAssertTrue(copy.contains("3"))
        XCTAssertEqual(BufferLayout.pasteTitle(count: 1, target: nil, canPaste: true), BufferLayout.pasteTitle(count: 1, target: nil, canPaste: false))
    }

    // MARK: Pasting a batch

    private func makeManager() throws -> (ScreenshotShelfManager, [URL], URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("amg-buffer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let manager = ScreenshotShelfManager(store: ScreenshotBatchStore(fileURL: nil, batchGap: { 900 }))
        let start = Date()
        var urls: [URL] = []
        for index in 0..<3 {
            let url = folder.appendingPathComponent("shot-\(index).png")
            try Data([UInt8(index)]).write(to: url)
            XCTAssertTrue(manager.store.add(url, capturedAt: start.addingTimeInterval(Double(index))))
            urls.append(url)
        }
        return (manager, urls, folder)
    }

    func testPasteTakesTheSelectedScreenshotsOrTheWholeBatch() throws {
        let (manager, urls, folder) = try makeManager()
        defer { try? FileManager.default.removeItem(at: folder) }
        let batch = try XCTUnwrap(manager.store.batches.first)
        XCTAssertEqual(manager.pasteURLs(for: batch), urls, "nothing chosen: all, in capture order")

        let middle = try XCTUnwrap(batch.items.first { $0.url == urls[1] })
        manager.click(middle, extend: false)
        XCTAssertEqual(manager.pasteURLs(for: batch), [urls[1]])
        XCTAssertEqual(manager.selectedCount(in: batch), 1)
        // The second click of a double-click keeps it chosen (it used to deselect it).
        manager.click(middle, extend: false, double: true)
        XCTAssertEqual(manager.pasteURLs(for: batch), [urls[1]])
    }

    func testPastingABatchCopiesItAsOurOwnAndPressesCommandV() async throws {
        let (manager, urls, folder) = try makeManager()
        defer { try? FileManager.default.removeItem(at: folder) }
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("io.github.amidamaru940.skerry.tests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let savedTrusted = ClipboardPaster.isAccessibilityTrusted
        let savedActivate = ClipboardPaster.activateTarget
        let savedPost = ClipboardPaster.postPasteKeystroke
        let savedPause = ClipboardPaster.pause
        let savedFrontmost = ClipboardPaster.frontmostProcessID
        let savedKeyboard = ClipboardPaster.islandHasKeyboard
        let savedReturn = ClipboardPaster.returnIslandKeyboard
        defer {
            ClipboardPaster.isAccessibilityTrusted = savedTrusted
            ClipboardPaster.activateTarget = savedActivate
            ClipboardPaster.postPasteKeystroke = savedPost
            ClipboardPaster.pause = savedPause
            ClipboardPaster.frontmostProcessID = savedFrontmost
            ClipboardPaster.islandHasKeyboard = savedKeyboard
            ClipboardPaster.returnIslandKeyboard = savedReturn
        }
        // One ⌘V per screenshot, each with that screenshot alone on the clipboard.
        var pastedNames: [[String]] = []
        ClipboardPaster.isAccessibilityTrusted = { true }
        ClipboardPaster.activateTarget = { _ in }
        ClipboardPaster.pause = { _ in }
        // The target is already in front and the island, clicked a moment
        // ago, holds the keyboard until it hands it back: the paste must hand
        // it back itself, or the run stops before the first ⌘V (23.10).
        ClipboardPaster.frontmostProcessID = { NSRunningApplication.current.processIdentifier }
        var keyboardReturned = false
        ClipboardPaster.returnIslandKeyboard = { keyboardReturned = true }
        ClipboardPaster.islandHasKeyboard = { !keyboardReturned }
        ClipboardPaster.postPasteKeystroke = {
            let copied = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]
            pastedNames.append(copied?.map(\.lastPathComponent) ?? [])
            XCTAssertTrue(ClipboardOwnWrites.isOwnWrite(pasteboard), "the history does not record it")
        }

        var closed = false
        let batch = try XCTUnwrap(manager.store.batches.first)
        let result = manager.paste(batch: batch, pasteboard: pasteboard, target: NSRunningApplication.current) { closed = true }

        XCTAssertEqual(result, .pasted)
        XCTAssertTrue(closed)
        await ClipboardPaster.pasteRun?.value
        XCTAssertEqual(pastedNames, urls.map { [$0.lastPathComponent] })
    }

    // MARK: Cards

    func testCardsSayWhatAFileOrLinkIs() {
        XCTAssertEqual(ClipboardCardText.fileTitle(names: ["report.pdf"]), "report.pdf")
        XCTAssertTrue(ClipboardCardText.fileTitle(names: ["a.png", "b.png", "c.png"]).contains("3"))
        let link = ClipboardCardText.link("https://www.example.org/docs/start?tab=2")
        XCTAssertEqual(link.host, "example.org")
        XCTAssertEqual(link.rest, "/docs/start?tab=2")
        XCTAssertEqual(ClipboardCardText.link("https://example.org/").rest, "")
        XCTAssertEqual(ClipboardCardText.link("https://ru.wikipedia.org/wiki/%D0%9C%D0%BE%D1%81%D0%BA%D0%B2%D0%B0").rest, "/wiki/Москва")
        XCTAssertEqual(ClipboardCardText.link("not a link").host, "not a link")
    }

    func testAPictureDragsAtItsOwnShape() {
        XCTAssertEqual(ClipboardDragPreview.size(for: CGSize(width: 1200, height: 600)), NSSize(width: 120, height: 60))
        XCTAssertEqual(ClipboardDragPreview.size(for: CGSize(width: 40, height: 80)), NSSize(width: 40, height: 80))
        XCTAssertEqual(ClipboardDragPreview.size(for: .zero), NSSize(width: 32, height: 32))
    }

    // MARK: Buffer v3 (docs/design/mockups/E/Buffer-v3.dc.html)

    func testTheFiltersAreFiveWordsInTheBoardsOrder() throws {
        XCTAssertEqual(BufferSegment.available(clipboard: true, screenshots: true).map(\.rawValue),
                       ["all", "screenshots", "text", "links", "files"])
        let path = try XCTUnwrap(Bundle.main.path(forResource: "ru", ofType: "lproj"))
        let ru = try XCTUnwrap(Bundle(path: path))
        XCTAssertEqual(ru.localizedString(forKey: "Shots", value: nil, table: nil), "Снимки", "«Скриншоты» → «Снимки» (the glossary)")
        XCTAssertEqual(ru.localizedString(forKey: "Recent items", value: nil, table: nil), "Недавнее")
        XCTAssertEqual(FilterWords<BufferSegment>.gap, 16)
    }

    func testTheFilmIsThreeFramesAcrossTheWidth() {
        XCTAssertEqual(ScreenshotGridLayout.spacing, 9)
        XCTAssertEqual(ScreenshotGridLayout.filmFrame(width: 570), CGSize(width: 184, height: 115))
        XCTAssertEqual(ScreenshotGridLayout.filmFrame(width: 0), DSE.Size.film, "before the width is known")
        for width in stride(from: CGFloat(400), through: 640, by: 13) {
            let frame = ScreenshotGridLayout.filmFrame(width: width)
            XCTAssertLessThanOrEqual(frame.width * 3 + ScreenshotGridLayout.spacing * 2, width, "three frames fit \(width)")
            XCTAssertEqual(frame.height, (frame.width * 0.625).rounded(), "16:10")
        }
        XCTAssertNil(ScreenshotGridLayout.filmMore(count: 3), "three shots: three frames")
        XCTAssertEqual(ScreenshotGridLayout.filmMore(count: 4), 2, "from four on the third frame is «+N»")
        XCTAssertEqual(ScreenshotGridLayout.filmMore(count: 9), 7)
    }

    func testTheThumbnailLineHasThreeSteps() {
        // 4, 3 and 2 frames a row across the 570 content.
        XCTAssertEqual(ScreenshotGridLayout.sizeSteps.map { ScreenshotGridLayout.columns(width: 570, minimumTile: $0).count }, [4, 3, 2])
        for step in ScreenshotGridLayout.sizeSteps { XCTAssertTrue((70...200).contains(step), "the setting keeps its range") }
        XCTAssertEqual(ScreenshotGridLayout.sizeStep(for: 110), 0, "the default is the first step")
        XCTAssertEqual(ScreenshotGridLayout.sizeStep(for: 70), 0)
        XCTAssertEqual(ScreenshotGridLayout.sizeStep(for: 150), 1)
        XCTAssertEqual(ScreenshotGridLayout.sizeStep(for: 200), 2)
        XCTAssertEqual(StepLine.step(atX: 0, length: 60, steps: 3), 0)
        XCTAssertEqual(StepLine.step(atX: 31, length: 60, steps: 3), 1)
        XCTAssertEqual(StepLine.step(atX: 75, length: 60, steps: 3), 2, "past the end: the last step")
    }

    func testRowsSayWhatAnEntryIs() {
        XCTAssertEqual(ClipboardRowText.title(for: ClipboardItem(stringData: "https://www.github.com/apple/swift/pull/42", type: .url)),
                       "github.com/apple/swift/pull/42")
        XCTAssertEqual(ClipboardRowText.title(for: ClipboardItem(stringData: "  Созвон\nперенесли \n\n на четверг ", type: .text)),
                       "Созвон перенесли на четверг", "one line")
        XCTAssertEqual(ClipboardRowText.title(for: ClipboardItem(fileURLs: ["file:///tmp/report.pdf"])), "report.pdf")
        XCTAssertTrue(ClipboardRowText.title(for: ClipboardItem(fileURLs: ["file:///tmp/a.png", "file:///tmp/b.png"])).hasSuffix(" · a.png, b.png"))
        XCTAssertTrue(ClipboardRowText.pictureTitle(CGSize(width: 1920, height: 1080)).hasSuffix(" · 1920 × 1080"))
        XCTAssertEqual(ClipboardRowText.truncation(for: .url), .middle)
        XCTAssertEqual(ClipboardRowText.truncation(for: .file), .middle)
        XCTAssertEqual(ClipboardRowText.truncation(for: .text), .tail)
        let tooltip = ClipboardRowText.tooltip(for: ClipboardItem(stringData: "line one\nline two", type: .text))
        XCTAssertTrue(tooltip.hasSuffix("\nline one\nline two"), "the whole text is in the tooltip")
    }

    func testAColourShowsWithASwatch() {
        XCTAssertEqual(ClipboardRowText.swatch("#5BBEEB"), 0x5BBEEB)
        XCTAssertEqual(ClipboardRowText.swatch(" #0a84ff\n"), 0x0A84FF)
        XCTAssertNil(ClipboardRowText.swatch("483921"), "a code is not a colour")
        XCTAssertNil(ClipboardRowText.swatch("#5BBEEG"))
        XCTAssertNil(ClipboardRowText.swatch("#5BBEEB is blue"))
        XCTAssertNil(ClipboardRowText.swatch(nil))
    }

    func testRowsFillTheLeftColumnFirst() {
        XCTAssertEqual(ClipboardRowText.leftColumnCount(0), 0)
        XCTAssertEqual(ClipboardRowText.leftColumnCount(1), 1)
        XCTAssertEqual(ClipboardRowText.leftColumnCount(6), 3, "1–3 on the left, 4–6 on the right")
        XCTAssertEqual(ClipboardRowText.leftColumnCount(5), 3)
        XCTAssertEqual(ClipboardRowText.gutter, 24)
    }

    func testTheRowTimeIsShort() throws {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "ru", ofType: "lproj"))
        let ru = try XCTUnwrap(Bundle(path: path))
        let locale = Locale(identifier: "ru_RU")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 12, minute: 36)))
        let yesterday = now.addingTimeInterval(-86_400)
        let earlier = now.addingTimeInterval(-86_400 * 3)
        XCTAssertEqual(DayTimeLabel.compact(for: yesterday, now: now, calendar: calendar, bundle: ru, locale: locale), "Вчера")
        let older = DayTimeLabel.compact(for: earlier, now: now, calendar: calendar, bundle: ru, locale: locale)
        XCTAssertFalse(older.contains(":"), "no time before yesterday: \(older)")
        XCTAssertTrue(DayTimeLabel.compact(for: now, now: now, calendar: calendar, bundle: ru, locale: locale).contains(":"))
    }

    func testThePasteKeyRemembersThreeApps() {
        var list: [String] = []
        for app in ["Claude", "Safari", "Claude", "Telegram", "Notes"] {
            list = RecentApps.remembering(app, in: list, same: ==)
        }
        XCTAssertEqual(list, ["Notes", "Telegram", "Claude"], "newest first, no repeats, three at most")
    }

    func testTheBufferRowsAndControlsDraw() throws {
        let pieces: [(String, AnyView, CGSize)] = [
            ("row-link", AnyView(ClipboardRow(item: ClipboardItem(stringData: "https://github.com/apple/swift/pull/42", type: .url), number: 1)), CGSize(width: 273, height: 22)),
            ("row-colour", AnyView(ClipboardRow(item: ClipboardItem(stringData: "#5BBEEB", type: .text), number: 3, isSelected: true)), CGSize(width: 273, height: 22)),
            ("row-pinned", AnyView(ClipboardRow(item: ClipboardItem(stringData: "Созвон перенесли на четверг", type: .text), number: 2, commandHeld: true, isPinned: true)), CGSize(width: 273, height: 22)),
            ("row-copied", AnyView(ClipboardRow(item: ClipboardItem(stringData: "483 921", type: .text), number: 6, justCopied: true)), CGSize(width: 273, height: 22)),
            ("row-removed", AnyView(RemovedClipboardRow {}), CGSize(width: 273, height: 22)),
            ("row-picture", AnyView(ClipboardRow(item: ClipboardItem(stringData: "", type: .image), number: 4)), CGSize(width: 273, height: ClipboardRow.pictureRowHeight)),
            ("filters", AnyView(FilterWords<BufferSegment>(items: BufferSegment.allCases.map { .init(id: $0, title: $0.title) }, selection: .all) { _ in }), CGSize(width: 360, height: 20)),
            ("notice-paused", AnyView(NoticeRow(symbol: "pause.circle", tint: DS.Palette.paused, title: "Paused", message: "new copies", actionTitle: "Resume", action: {})), CGSize(width: 570, height: 32)),
            ("step-line", AnyView(StepLine(steps: 3, selected: 1, label: "Size") { _ in }), CGSize(width: 60, height: 28)),
            ("paste-key", AnyView(SplitPasteKey(action: {}, arrowAction: {}) { Text(verbatim: "Вставить в Claude · 3") }), CGSize(width: 240, height: 32)),
            ("action-row-toast", AnyView(ActionRowToast(symbol: "exclamationmark.circle", tint: DS.Palette.attention, message: BufferTabState.copiedHint)), CGSize(width: 440, height: 32)),
        ]
        let folder = ProcessInfo.processInfo.environment["SKERRY_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
        for (name, view, size) in pieces {
            let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height).padding(8).background(Color.black).environment(\.colorScheme, .dark))
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.nsImage, name)
            XCTAssertGreaterThan(image.size.width, 0)
            if let folder, let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try png.write(to: folder.appendingPathComponent("\(name).png"))
            }
        }
    }

    // MARK: Buffer v3 review (parity БЛОК)

    func testTheShotsShortcutOpensShotsAndClosesThem() {
        typealias Action = BufferLayout.ShotsShortcut
        XCTAssertEqual(BufferLayout.shotsShortcut(islandOpen: false, onBuffer: true, segment: .text),
                       Action(showsShots: true, togglesTab: true), "closed: opens «Буфер» on «Снимки»")
        XCTAssertEqual(BufferLayout.shotsShortcut(islandOpen: true, onBuffer: false, segment: .all),
                       Action(showsShots: true, togglesTab: true), "on another tab: «Буфер» on «Снимки»")
        XCTAssertEqual(BufferLayout.shotsShortcut(islandOpen: true, onBuffer: true, segment: .links),
                       Action(showsShots: true, togglesTab: false), "another filter: moves to «Снимки», stays open")
        XCTAssertEqual(BufferLayout.shotsShortcut(islandOpen: true, onBuffer: true, segment: .screenshots),
                       Action(showsShots: false, togglesTab: true), "pressed again on «Снимки»: closes")
    }

    func testTheShotsShortcutMovesTheBufferToShots() {
        // tests/test_permission_prompts.py: only components/ call startOnFirstUse().
        let state = BufferTabState.shared
        let saved = state.segment
        defer { state.segment = saved }
        state.segment = .text
        ScreenshotShelfManager(store: ScreenshotBatchStore(fileURL: nil, batchGap: { 900 })).openShotsByRequest()
        XCTAssertEqual(state.segment, .screenshots)
    }

    func testANewScreenshotMovesOtherFiltersToAll() {
        XCTAssertEqual(BufferLayout.segmentAfterCapture(.all), .all)
        XCTAssertEqual(BufferLayout.segmentAfterCapture(.screenshots), .screenshots, "«Снимки» already shows the new batch")
        for segment in [BufferSegment.text, .links, .files] {
            XCTAssertEqual(BufferLayout.segmentAfterCapture(segment), .all, "\(segment): the film and its key are under «Все»")
        }
    }

    func testClearHistoryIsOfferedOnlyWhereItsUndoIsSeen() {
        for segment in [BufferSegment.all, .text, .links, .files] {
            XCTAssertTrue(BufferLayout.offersClearHistory(segment: segment, hidingContent: false), "\(segment)")
            XCTAssertFalse(BufferLayout.offersClearHistory(segment: segment, hidingContent: true), "\(segment) while the screen is shared")
        }
        XCTAssertTrue(BufferLayout.offersClearHistory(segment: .screenshots, hidingContent: false), "«Снимки»: the screenshots go")
        XCTAssertFalse(BufferLayout.offersClearHistory(segment: .screenshots, hidingContent: true))
        XCTAssertFalse(BufferLayout.offersClearHistory(segment: nil, hidingContent: false), "clipboard off")
        // Moved to «Снимки» during the offer: «Отменить» rides a capsule.
        XCTAssertTrue(BufferLayout.clearedUndoNeedsCapsule(segment: .screenshots, undo: .history))
        XCTAssertFalse(BufferLayout.clearedUndoNeedsCapsule(segment: .all, undo: .history), "the history shows its own line")
        XCTAssertFalse(BufferLayout.clearedUndoNeedsCapsule(segment: .screenshots, undo: .row(itemID: UUID(), index: 0, pinned: false)))
        XCTAssertFalse(BufferLayout.clearedUndoNeedsCapsule(segment: .screenshots, undo: nil))
    }

    func testClearHistoryIsNotInTheMenuOnShots() {
        let offered = IslandMoreMenu.Features(clipboard: true, clipboardHistoryCount: 4)
        XCTAssertEqual(IslandMoreMenu.entries(for: offered).first, .clearClipboardHistory(count: 4))
        let notOffered = IslandMoreMenu.Features(clipboard: true, clipboardHistoryCount: nil)
        XCTAssertFalse(IslandMoreMenu.entries(for: notOffered).contains { if case .clearClipboardHistory = $0 { return true } else { return false } })
    }

    func testTheQueryGoesWhenTheTabLeavesTheScreen() {
        let state = BufferTabState()
        state.openSearch()
        state.query = "отчёт"
        state.submitSearch()                 // ↩ pastes the first find, the island closes
        XCTAssertEqual(state.searchSubmits, 1)
        state.tabDisappeared()
        XCTAssertFalse(state.searching, "the field is closed at the next opening")
        XCTAssertEqual(state.query, "", "no invisible filter is left")

        state.openSearch()
        state.query = "x"
        state.closeSearch()
        XCTAssertEqual(state.query, "")
    }

    func testThePasteArrowSkipsFinderSkerryAndQuitApps() {
        struct App: Equatable { let name: String; let bundleID: String?; var quit = false }
        let apps = [
            App(name: "Claude", bundleID: "com.anthropic.claudefordesktop"),
            App(name: "Finder", bundleID: "com.apple.finder"),
            App(name: "Skerry", bundleID: "io.example.skerry"),
            App(name: "Safari", bundleID: "com.apple.Safari", quit: true),
            App(name: "Tool", bundleID: nil),
        ]
        let targets = RecentApps.targets(apps, bundleID: \.bundleID, isTerminated: \.quit, own: "io.example.skerry")
        XCTAssertEqual(targets.map(\.name), ["Claude", "Tool"])
        XCTAssertFalse(RecentApps.isPasteTarget(bundleID: "com.apple.finder", own: "io.example.skerry"), "never remembered for the arrow")
        XCTAssertFalse(RecentApps.isPasteTarget(bundleID: Bundle.main.bundleIdentifier), "never Skerry itself")
        XCTAssertTrue(RecentApps.isPasteTarget(bundleID: "com.tdesktop.Telegram", own: "io.example.skerry"))
        // A system prompt or a menu-bar agent that came forward is no target.
        XCTAssertTrue(RecentApps.isUserApp(.regular))
        XCTAssertFalse(RecentApps.isUserApp(.accessory), "universalAccessAuthWarn, menu-bar agents")
        XCTAssertFalse(RecentApps.isUserApp(.prohibited))
    }

    func testSettingsOpenOnTheAskedPageTheFirstTimeToo() {
        // The page is set before the window shows; the view takes it once.
        SettingsWindowController.request(page: SettingsWindowController.clipboardPage)
        XCTAssertEqual(SettingsWindowController.requestedPage, "clipboard")
        XCTAssertEqual(SettingsWindowController.takeRequestedPage(), "clipboard")
        XCTAssertNil(SettingsWindowController.takeRequestedPage(), "taken once: a later opening keeps its own page")
    }

    func testOldThumbnailSizesLandOnASteps() {
        XCTAssertEqual(ScreenshotGridLayout.sizeStep(for: 70), 0, "the old smallest size: the first step")
        XCTAssertEqual(ScreenshotGridLayout.sizeStep(for: 135), 0, "halfway between the first two: the smaller")
        XCTAssertEqual(ScreenshotGridLayout.sizeStep(for: 136), 1)
        XCTAssertEqual(ScreenshotGridLayout.sizeStep(for: 185), 2)
    }

    func testAPictureRowGetsASmallThumbnailAndTheRealSize() throws {
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 400, pixelsHigh: 200, bitsPerSample: 8,
                                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let thumbnail = try XCTUnwrap(ClipboardThumbnails.make(from: png))
        XCTAssertLessThanOrEqual(max(thumbnail.image.width, thumbnail.image.height), ClipboardThumbnails.maxPixelSide, "2× the 56 × 36 frame, not the picture")
        XCTAssertEqual(thumbnail.pixelSize, CGSize(width: 400, height: 200), "the title still says the picture's size")
        XCTAssertNil(ClipboardThumbnails.make(from: Data([1, 2, 3])))
    }

    /// Owner, 22.10: «непонятно, что за скрин». A picture row is two row
    /// pitches with a thumbnail of at least 48 × 30, and a preview about
    /// 280 pt wide opens while the pointer rests on it.
    func testAPictureRowIsRecognisable() {
        XCTAssertEqual(ClipboardRow.pictureRowHeight, DSE.Size.rowPitch * 2, "both columns stay on the 22 pt grid")
        XCTAssertGreaterThanOrEqual(ClipboardRow.pictureThumbnail.width, 48)
        XCTAssertGreaterThanOrEqual(ClipboardRow.pictureThumbnail.height, 30)
        XCTAssertLessThanOrEqual(ClipboardRow.pictureThumbnail.height, ClipboardRow.pictureRowHeight - 6)
        XCTAssertEqual(ClipboardThumbnails.maxPixelSide, Int(ClipboardRow.pictureThumbnail.width * 2))
        XCTAssertEqual(ClipboardPicturePreview.width + 2 * ClipboardPicturePreview.inset, 280, accuracy: 1)

        // A MacBook screenshot fills the width; a small picture stays at its size; a tall one fits the height.
        XCTAssertEqual(ClipboardPicturePreview.size(for: CGSize(width: 3456, height: 2234)), CGSize(width: 260, height: 168))
        XCTAssertEqual(ClipboardPicturePreview.size(for: CGSize(width: 200, height: 100)), CGSize(width: 100, height: 50))
        XCTAssertEqual(ClipboardPicturePreview.size(for: CGSize(width: 1000, height: 4000)), CGSize(width: 75, height: 300))
        XCTAssertEqual(ClipboardPicturePreview.size(for: .zero).width, ClipboardPicturePreview.width)
        XCTAssertEqual(ClipboardRowText.pixelSize(CGSize(width: 3456, height: 2234)), "3456 × 2234")
    }

    func testAPicturePreviewIsDecodedAtItsOwnSize() throws {
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 3456, pixelsHigh: 2234, bitsPerSample: 8,
                                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let preview = try XCTUnwrap(ClipboardThumbnails.make(from: png, maxPixelSide: ClipboardThumbnails.previewPixelSide))
        XCTAssertEqual(max(preview.image.width, preview.image.height), ClipboardThumbnails.previewPixelSide, "2× the preview, never the full picture")
    }

    /// Review 22.10: the preview opens beside the row, past the column's
    /// outer edge, and stays on the screen; VoiceOver reads a picture's
    /// origin and time, since it has no tooltip.
    func testThePicturePreviewOpensBesideTheRowAndAPictureSaysWhereItCameFrom() {
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1084)
        let row = CGRect(x: 600, y: 900, width: 273, height: 44)
        let size = CGSize(width: 280, height: 220)
        let left = ClipboardPreviewPanel.frame(size: size, beside: row, edge: .leading, screen: screen)
        XCTAssertEqual(left.maxX, row.minX - ClipboardPreviewPanel.gap)
        XCTAssertEqual(left.midY, row.midY)
        let right = ClipboardPreviewPanel.frame(size: size, beside: row, edge: .trailing, screen: screen)
        XCTAssertEqual(right.minX, row.maxX + ClipboardPreviewPanel.gap)
        let high = ClipboardPreviewPanel.frame(size: size, beside: row.offsetBy(dx: 0, dy: 150), edge: .trailing, screen: screen)
        XCTAssertEqual(high.maxY, screen.maxY, "kept on the screen")

        let picture = ClipboardItem(stringData: "", type: .image)
        let now = Date()
        let label = ClipboardRowText.accessibilityLabel(for: picture, pixelSize: CGSize(width: 3456, height: 2234), now: now)
        XCTAssertTrue(label.hasPrefix(ClipboardRowText.pictureTitle(CGSize(width: 3456, height: 2234))))
        XCTAssertTrue(label.hasSuffix(ClipboardRowText.origin(for: picture, now: now)))
    }

    /// Without access to the screenshot folder, «Снимки» shows only the
    /// temporary clipboard shots, by the path's text: saved ones would be blank.
    func testWithoutFolderAccessOnlyClipboardShotsShow() {
        let temporary = TemporaryClipboardShots.folder.appendingPathComponent("shot.png").path
        let saved = "/Users/someone/Desktop/Screenshot.png"
        let now = Date()
        let mixed = ScreenshotBatch(id: UUID(), items: [
            ScreenshotItem(path: saved, capturedAt: now),
            ScreenshotItem(path: temporary, capturedAt: now),
        ], lastAddedAt: now)
        let savedOnly = ScreenshotBatch(id: UUID(), items: [ScreenshotItem(path: saved, capturedAt: now)], lastAddedAt: now)

        let shown = ScreenshotBatchPanel.visibleBatches([mixed, savedOnly], onlyClipboardShots: true)
        XCTAssertEqual(shown.map(\.id), [mixed.id], "a batch of saved shots only is left out")
        XCTAssertEqual(shown.first?.items.map(\.path), [temporary])
        XCTAssertEqual(ScreenshotBatchPanel.visibleBatches([mixed, savedOnly], onlyClipboardShots: false), [mixed, savedOnly])
    }

    // MARK: One tab instead of two

    func testScreenshotsAreShownInTheClipboardTab() {
        XCTAssertTrue(NotchTab.screenshots.isMergedIntoClipboard)
        XCTAssertEqual(NotchTab.screenshots.shownAs, .clipboard)
        XCTAssertEqual(NotchTab.shelf.shownAs, .shelf)
        XCTAssertEqual(IslandKeyboard.action(for: .close, current: .clipboard, visible: [.clipboard], hasScreenshotSelection: true),
                       .clearScreenshotSelection, "Esc first clears the chosen screenshots")
        XCTAssertEqual(IslandKeyboard.action(for: .close, current: .clipboard, visible: [.clipboard], hasScreenshotSelection: false), .close)
    }

    // MARK: Drawing

    func testTheBatchStripAndCardsDraw() throws {
        let card = ClipboardCard(item: ClipboardItem(stringData: "https://www.example.org/docs/start", type: .url), number: 1,
                                 isHovered: false, isSelected: false, justCopied: false)
        let files = ClipboardCard(item: ClipboardItem(fileURLs: ["file:///tmp/a.png", "file:///tmp/b.png"]), number: 2,
                                  isHovered: true, isSelected: true, justCopied: false)
        let pieces: [(String, AnyView, CGSize)] = [
            ("card-link", AnyView(card), CGSize(width: 220, height: 70)),
            ("card-files", AnyView(files), CGSize(width: 220, height: 70)),
            ("toast", AnyView(DSToastView(text: BufferTabState.copiedHint, tone: .warning)), CGSize(width: 560, height: 40)),
            ("segments", AnyView(DSSegmented(options: BufferSegment.allCases.map { (value: $0, title: $0.title) }, selection: .constant(.all))), CGSize(width: 420, height: 30)),
        ]
        let folder = ProcessInfo.processInfo.environment["SKERRY_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
        for (name, view, size) in pieces {
            let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height).padding(8).background(Color.black).environment(\.colorScheme, .dark))
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.nsImage, name)
            XCTAssertGreaterThan(image.size.width, 0)
            if let folder, let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try png.write(to: folder.appendingPathComponent("\(name).png"))
            }
        }
    }
}
