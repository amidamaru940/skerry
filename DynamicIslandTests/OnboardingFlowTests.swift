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

/// Step D7: three steps, no profiles, resume where it was left.
final class OnboardingFlowTests: XCTestCase {
    func testThreeStepsWithBackAndNext() {
        XCTAssertEqual(OnboardingFlow.Step.allCases, [.hello, .features, .permission])
        XCTAssertEqual(OnboardingFlow.Step.hello.next, .features)
        XCTAssertEqual(OnboardingFlow.Step.permission.next, nil, "then Done")
        XCTAssertNil(OnboardingFlow.Step.hello.previous)
        XCTAssertEqual(OnboardingFlow.Step.permission.previous, .features)
        XCTAssertEqual(OnboardingFlow.Step.permission.number, 3)
    }

    func testQuittingHalfWayResumesAtTheSameStep() {
        XCTAssertEqual(OnboardingFlow.resumeStep(saved: "permission"), .permission)
        XCTAssertEqual(OnboardingFlow.resumeStep(saved: nil), .hello)
        XCTAssertEqual(OnboardingFlow.resumeStep(saved: "profiles"), .hello, "an old or unknown value starts over")
        XCTAssertTrue(OnboardingFlow.isNeeded(completed: false, firstLaunch: false, savedStep: "features"))
        XCTAssertTrue(OnboardingFlow.isNeeded(completed: false, firstLaunch: true, savedStep: nil))
    }

    func testWhoeverFinishedIsNotAskedAgain() {
        XCTAssertFalse(OnboardingFlow.isNeeded(completed: true, firstLaunch: true, savedStep: "features"))
        // Went through the old onboarding: first launch behind, nothing saved.
        XCTAssertFalse(OnboardingFlow.isNeeded(completed: false, firstLaunch: false, savedStep: nil))
        XCTAssertFalse(Defaults.Keys.onboardingCompleted.defaultValue)
        XCTAssertNil(Defaults.Keys.onboardingStep.defaultValue)
    }

    func testStepTwoOffersFiveLocalFeaturesAndNothingNetworked() {
        let features = OnboardingFlow.features
        XCTAssertEqual(features.map(\.id), ["clipboard", "screenshots", "music", "calendar", "terminal"])
        let keys = features.map(\.key.name)
        for networked in ["enableLyrics", "enableScreenAssistant", "enableLLMUsageFeature", "enableLocalSend", "showMirror"] {
            XCTAssertFalse(keys.contains(networked), networked)
        }
        for feature in features {
            XCTAssertFalse(String(localized: feature.permission).isEmpty, feature.id)
        }
    }

    /// §5.8: «Continue» on step two with Screenshots on is when the
    /// screenshot folder is first looked at (and macOS may ask), not launch.
    func testContinueOnStepTwoWithScreenshotsOnStartsThem() {
        XCTAssertTrue(OnboardingFlow.startsScreenshots(leaving: .features, for: .permission, screenshotsOn: true))
        XCTAssertFalse(OnboardingFlow.startsScreenshots(leaving: .features, for: .permission, screenshotsOn: false),
                       "turned off on step two")
        XCTAssertFalse(OnboardingFlow.startsScreenshots(leaving: .features, for: .hello, screenshotsOn: true), "Back")
        XCTAssertFalse(OnboardingFlow.startsScreenshots(leaving: .hello, for: .features, screenshotsOn: true), "step one")
        XCTAssertFalse(OnboardingFlow.startsScreenshots(leaving: .permission, for: .features, screenshotsOn: true), "Back from three")
    }

    /// Screenshots are one feature (owner, 22.10): the step-two switch also
    /// collects those taken to the clipboard, and turns them off with it.
    func testTheScreenshotsSwitchAlsoCollectsClipboardScreenshots() throws {
        let shelf = Defaults[.enableScreenshotShelf], collect = Defaults[.collectClipboardScreenshots]
        let clipboard = Defaults[.enableClipboardManager]
        defer {
            Defaults[.enableScreenshotShelf] = shelf
            Defaults[.collectClipboardScreenshots] = collect
            Defaults[.enableClipboardManager] = clipboard
        }
        let screenshots = try XCTUnwrap(OnboardingFlow.features.first { $0.id == "screenshots" })

        OnboardingFlow.setFeature(screenshots, on: false)
        XCTAssertFalse(Defaults[.enableScreenshotShelf])
        XCTAssertFalse(Defaults[.collectClipboardScreenshots], "off with the switch")
        XCTAssertFalse(ClipboardScreenshotDetector.routesToScreenshots)

        OnboardingFlow.setFeature(screenshots, on: true)
        XCTAssertTrue(Defaults[.enableScreenshotShelf])
        XCTAssertTrue(Defaults[.collectClipboardScreenshots], "on with the switch")
        XCTAssertTrue(ClipboardScreenshotDetector.routesToScreenshots, "⌃⇧⌘4 goes to the batches")

        // Another switch sets only its own key.
        let clipboardFeature = try XCTUnwrap(OnboardingFlow.features.first { $0.id == "clipboard" })
        OnboardingFlow.setFeature(clipboardFeature, on: false)
        XCTAssertFalse(Defaults[.enableClipboardManager])
        XCTAssertTrue(Defaults[.collectClipboardScreenshots])
    }

    /// Draws each step; with SKERRY_SNAPSHOT_DIR set the pictures are saved.
    @MainActor
    func testEachStepDraws() throws {
        let saved = Defaults[.onboardingStep]
        defer { Defaults[.onboardingStep] = saved }
        let folder = ProcessInfo.processInfo.environment["SKERRY_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
        for step in OnboardingFlow.Step.allCases {
            Defaults[.onboardingStep] = step.rawValue
            let renderer = ImageRenderer(content: OnboardingFlowView(onFinish: {}).background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .dark))
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.nsImage, step.rawValue)
            XCTAssertEqual(image.size.width, 440, accuracy: 1)
            if let folder, let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try png.write(to: folder.appendingPathComponent("onboarding-\(step.rawValue).png"))
            }
        }
    }
}
