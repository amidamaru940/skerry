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

import Defaults
import Foundation

/// Folders macOS guards (Desktop, Downloads, Documents). The first touch of
/// one by a build macOS has not seen before asks the person, and the call
/// blocks until they answer. On the main thread at launch that held the
/// whole app with no island (21.10: `sample` showed launch stuck in
/// DownloadManager.init and ScreenshotShelfManager.start, each in open()).
///
/// So the first touch happens on a utility queue, and the caller carries on
/// on the main actor once macOS has answered, whatever the answer was: a
/// refused folder simply reads as empty to the code that follows.
enum ProtectedFolder {
    static func touch(_ folder: URL?, then continuation: @escaping @MainActor @Sendable () -> Void) {
        DispatchQueue.global(qos: .utility).async {
            if let folder {
                _ = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            }
            Task { @MainActor in continuation() }
        }
    }
}

/// When a protected folder is looked at for the first time. Not at launch
/// on a fresh install: only after the person asked for the feature that
/// needs it, and from then on at launch too, which a stored flag per folder
/// records (`screenshotFolderTouched`, `downloadsFolderTouched`,
/// `documentsFolderTouched`; docs/design/REDESIGN-SPEC.md §5.8). The
/// screenshot folder can move, so its flag holds for the folder it was
/// earned in (`screenshotFolderTouchedPath`).
///
/// TODO(R11, PermissionKind): the Desktop and Downloads rows read these
/// flags and show notDetermined while one is unset; a row never lists a
/// folder to learn its status ("unknown until asked", as
/// ShelfFolderAccessPermissionStore does today).
enum FolderFirstTouch {
    /// Whether Skerry ran on this Mac before this launch, and so looked at
    /// its folders at launch the way builds before the flags did.
    ///
    /// `firstLaunch` is written false once the first launch's hello has
    /// played. The onboarding, the screenshot batches and a screenshot
    /// switch flipped by hand (only the person writes those keys) count
    /// too, for an install that quit during the hello.
    static func launchedBefore(
        storedFirstLaunch: Any?,
        onboardingCompleted: Bool,
        onboardingStep: String?,
        hasScreenshotBatches: Bool,
        screenshotSwitchesSaved: Bool
    ) -> Bool {
        (storedFirstLaunch as? Bool) == false || onboardingCompleted || onboardingStep != nil
            || hasScreenshotBatches || screenshotSwitchesSaved
    }

    /// The same, read from what the app itself stored. Only its persistent
    /// domain counts: `UserDefaults.standard` also hands back the default
    /// each `Defaults.Key` registers at its first use, so the screenshot
    /// switches always read as saved and a fresh install looked like an
    /// earlier one (AppLanguage reads its key the same way).
    static func launchedBefore(
        storedIn defaults: UserDefaults = .standard,
        domain: String = Bundle.main.bundleIdentifier ?? "",
        hasScreenshotBatches: Bool
    ) -> Bool {
        let stored = defaults.persistentDomain(forName: domain) ?? [:]
        return launchedBefore(
            // DynamicIslandViewCoordinator.firstLaunch, an @AppStorage key.
            storedFirstLaunch: stored["firstLaunch"],
            onboardingCompleted: stored[Defaults.Keys.onboardingCompleted.name] as? Bool == true,
            onboardingStep: stored[Defaults.Keys.onboardingStep.name] as? String,
            hasScreenshotBatches: hasScreenshotBatches,
            screenshotSwitchesSaved: [Defaults.Keys.enableScreenshotShelf.name, Defaults.Keys.collectClipboardScreenshots.name]
                .contains { stored[$0] != nil }
        )
    }

    /// `screenshotFolderTouchedPath` on an install that ran an earlier
    /// build: launch looks at the screenshot folder wherever it is, as those
    /// builds did. Never a real path, which starts with "/".
    static let anyScreenshotFolder = "*"

    /// Whether launch may look at the screenshot folder `current`: only the
    /// folder macOS last answered for after the person asked, or any folder
    /// on an earlier install. A folder moved into the Desktop while Skerry
    /// was not running would otherwise be asked for at launch, with no click.
    static func launchLooksAtScreenshotFolder(_ current: URL, touched: Bool, touchedPath: String?) -> Bool {
        touched && (touchedPath == anyScreenshotFolder || touchedPath == current.standardizedFileURL.path)
    }

    /// What `screenshotFolderTouchedPath` becomes once macOS has answered
    /// for `folder`. An earlier install keeps its any-folder marker.
    static func touchedPath(_ stored: String?, afterAnswerFor folder: URL) -> String {
        stored == anyScreenshotFolder ? anyScreenshotFolder : folder.standardizedFileURL.path
    }
}
