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
import XCTest

/// To macOS the unit-test host is an app of its own, so whatever it asked
/// for at launch -- Accessibility, Calendar, Bluetooth, the keyboard tap --
/// came up on screen on every test run.
final class PermissionPromptTests: XCTestCase {
    func testTheTestHostNeverAsksForPermissions() {
        XCTAssertTrue(AppRuntimeEnvironment.isHostingUnitTests)
        XCTAssertFalse(AppRuntimeEnvironment.mayAskForPermissions)
    }

    func testTheMediaKeyTapIsNotInstalledUnderTests() {
        XCTAssertFalse(MediaKeyInterceptor.shared.start())
    }

    /// The test host's island took the keyboard from the chat the person was
    /// typing in, and showed a second island over the real one.
    @MainActor
    func testTheTestHostsIslandIsNeverShownNorKey() {
        let window = DynamicIslandWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        XCTAssertFalse(window.isVisible)
        XCTAssertFalse(window.canBecomeKey)
        XCTAssertFalse(window.isKeyWindow)
    }
}

/// §5.8: a fresh install looks at no protected folder at launch. Builds
/// before the first-touch flags looked at the screenshot folder at every
/// launch, so an install that ran one is given the flags and starts as it did.
final class FolderFirstTouchTests: XCTestCase {
    private func launchedBefore(
        storedFirstLaunch: Any? = nil,
        onboardingCompleted: Bool = false,
        onboardingStep: String? = nil,
        hasScreenshotBatches: Bool = false,
        screenshotSwitchesSaved: Bool = false
    ) -> Bool {
        FolderFirstTouch.launchedBefore(
            storedFirstLaunch: storedFirstLaunch,
            onboardingCompleted: onboardingCompleted,
            onboardingStep: onboardingStep,
            hasScreenshotBatches: hasScreenshotBatches,
            screenshotSwitchesSaved: screenshotSwitchesSaved
        )
    }

    func testAFreshInstallHasNotLaunchedBefore() {
        XCTAssertFalse(launchedBefore())
    }

    func testAnEarlierInstallIsKnownByAnyOfItsTraces() {
        XCTAssertTrue(launchedBefore(storedFirstLaunch: false), "the hello has played")
        XCTAssertTrue(launchedBefore(onboardingCompleted: true), "onboarding finished or skipped")
        XCTAssertTrue(launchedBefore(onboardingStep: "features"), "onboarding left half way")
        XCTAssertTrue(launchedBefore(hasScreenshotBatches: true), "screenshots were collected")
        XCTAssertTrue(launchedBefore(screenshotSwitchesSaved: true), "a screenshot switch was flipped")
    }

    /// `@AppStorage("firstLaunch")` only ever writes false.
    func testOnlyAStoredFalseCountsAsAnEarlierLaunch() {
        XCTAssertFalse(launchedBefore(storedFirstLaunch: true))
        XCTAssertFalse(launchedBefore(storedFirstLaunch: "false"))
        XCTAssertTrue(launchedBefore(storedFirstLaunch: NSNumber(value: false)), "how UserDefaults hands it back")
    }

    func testEveryFlagStartsUnsetSoAFreshInstallWaits() {
        XCTAssertFalse(Defaults.Keys.screenshotFolderTouched.defaultValue)
        XCTAssertNil(Defaults.Keys.screenshotFolderTouchedPath.defaultValue)
        XCTAssertFalse(Defaults.Keys.downloadsFolderTouched.defaultValue)
        XCTAssertFalse(Defaults.Keys.documentsFolderTouched.defaultValue)
        XCTAssertFalse(Defaults.Keys.didMigrateFolderFirstTouch.defaultValue)
    }

    /// Each `Defaults.Key` registers its default at its first use, and the
    /// merged view hands it back as if stored: read that way, every fresh
    /// install looked like an earlier one and was asked at launch.
    func testRegisteredDefaultsAreNoTraceOfAnEarlierLaunch() {
        let name = "Atoll.FolderFirstTouchTests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        defer { suite.removePersistentDomain(forName: name) }
        // What the app's own keys do to the standard suite.
        let shelf = Defaults.Key<Bool>(Defaults.Keys.enableScreenshotShelf.name, default: true, suite: suite)
        _ = Defaults.Key<Bool>(Defaults.Keys.collectClipboardScreenshots.name, default: false, suite: suite)
        _ = Defaults.Key<Bool>(Defaults.Keys.onboardingCompleted.name, default: false, suite: suite)
        XCTAssertNotNil(suite.object(forKey: shelf.name), "the merged view sees the registered default")
        XCTAssertFalse(FolderFirstTouch.launchedBefore(storedIn: suite, domain: name, hasScreenshotBatches: false))
        XCTAssertTrue(FolderFirstTouch.launchedBefore(storedIn: suite, domain: name, hasScreenshotBatches: true))

        suite.set(false, forKey: "firstLaunch")
        XCTAssertTrue(FolderFirstTouch.launchedBefore(storedIn: suite, domain: name, hasScreenshotBatches: false),
                      "the hello has played")
    }

    func testEveryStoredTraceCounts() {
        let traces: [(String, (UserDefaults) -> Void)] = [
            ("onboarding finished or skipped", { Defaults[Defaults.Key<Bool>(Defaults.Keys.onboardingCompleted.name, default: false, suite: $0)] = true }),
            ("onboarding left half way", { Defaults[Defaults.Key<String?>(Defaults.Keys.onboardingStep.name, default: nil, suite: $0)] = "features" }),
            ("screenshots turned off by hand", { Defaults[Defaults.Key<Bool>(Defaults.Keys.enableScreenshotShelf.name, default: true, suite: $0)] = false }),
            ("clipboard screenshots turned on", { Defaults[Defaults.Key<Bool>(Defaults.Keys.collectClipboardScreenshots.name, default: false, suite: $0)] = true }),
        ]
        for (trace, write) in traces {
            let name = "Atoll.FolderFirstTouchTests.\(UUID().uuidString)"
            let suite = UserDefaults(suiteName: name)!
            defer { suite.removePersistentDomain(forName: name) }
            write(suite)
            XCTAssertTrue(FolderFirstTouch.launchedBefore(storedIn: suite, domain: name, hasScreenshotBatches: false), trace)
        }
    }

    /// The flag holds for the folder macOS answered for: a folder moved into
    /// the Desktop while Skerry was not running is not looked at at launch.
    func testLaunchLooksOnlyAtTheScreenshotFolderMacOSAnsweredFor() {
        let screenshots = URL(fileURLWithPath: "/Users/someone/Screenshots", isDirectory: true)
        let desktop = URL(fileURLWithPath: "/Users/someone/Desktop", isDirectory: true)
        let answered = FolderFirstTouch.touchedPath(nil, afterAnswerFor: screenshots)

        XCTAssertTrue(FolderFirstTouch.launchLooksAtScreenshotFolder(screenshots, touched: true, touchedPath: answered))
        XCTAssertFalse(FolderFirstTouch.launchLooksAtScreenshotFolder(desktop, touched: true, touchedPath: answered))
        XCTAssertFalse(FolderFirstTouch.launchLooksAtScreenshotFolder(screenshots, touched: false, touchedPath: answered))
        XCTAssertFalse(FolderFirstTouch.launchLooksAtScreenshotFolder(screenshots, touched: true, touchedPath: nil))
        XCTAssertFalse(FolderFirstTouch.launchLooksAtScreenshotFolder(screenshots, touched: false, touchedPath: nil),
                       "a fresh install")

        // Followed into the Desktop while running: the Desktop from then on.
        let moved = FolderFirstTouch.touchedPath(answered, afterAnswerFor: desktop)
        XCTAssertTrue(FolderFirstTouch.launchLooksAtScreenshotFolder(desktop, touched: true, touchedPath: moved))
        XCTAssertFalse(FolderFirstTouch.launchLooksAtScreenshotFolder(screenshots, touched: true, touchedPath: moved))
    }

    /// Earlier builds followed the folder wherever it went, at launch too.
    func testAnEarlierInstallLooksAtAnyScreenshotFolderAsBefore() {
        let desktop = URL(fileURLWithPath: "/Users/someone/Desktop", isDirectory: true)
        let marker = FolderFirstTouch.anyScreenshotFolder
        XCTAssertFalse(marker.hasPrefix("/"), "never a real folder")
        XCTAssertTrue(FolderFirstTouch.launchLooksAtScreenshotFolder(desktop, touched: true, touchedPath: marker))
        XCTAssertEqual(FolderFirstTouch.touchedPath(marker, afterAnswerFor: desktop), marker)
    }
}
