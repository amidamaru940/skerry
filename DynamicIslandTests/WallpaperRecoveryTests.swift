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

/// A Skerry that crashed while the lock-screen artwork was shown left the wallpaper
/// store rewritten and the user's wallpaper in a backup. The next launch puts it back
/// while the store is still Skerry's, and drops the backup once the user chose another
/// wallpaper. Everything here runs in a temporary folder of its own: never against the
/// real com.apple.wallpaper store, and never with backup names in the temporary folder
/// itself, where a launch of the installed Skerry would find them.
final class WallpaperRecoveryTests: XCTestCase {
    private typealias Manager = FullScreenArtworkWindowManager
    private typealias BackupName = FullScreenArtworkWindowManager.BackupName

    private var root: URL!
    private var store: URL!
    private var backups: URL!
    private var legacyBackups: URL!
    private var restarts = 0

    private var index: URL { store.appendingPathComponent("Store/Index.plist") }
    private var manifest: URL { store.appendingPathComponent("aerials/manifest/entries.json") }
    private var video: URL { store.appendingPathComponent("aerials/videos/\(Manager.customLiveWallpaperAssetID).mov") }
    private var thumbnail: URL { store.appendingPathComponent("aerials/thumbnails/\(Manager.customLiveWallpaperAssetID).png") }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WallpaperRecoveryTests-\(UUID().uuidString)", isDirectory: true)
        store = root.appendingPathComponent("com.apple.wallpaper", isDirectory: true)
        backups = root.appendingPathComponent("Wallpaper backup", isDirectory: true)
        legacyBackups = root.appendingPathComponent("legacy tmp", isDirectory: true)
        restarts = 0
        for folder in [
            store.appendingPathComponent("Store"),
            store.appendingPathComponent("aerials/manifest"),
            store.appendingPathComponent("aerials/videos"),
            store.appendingPathComponent("aerials/thumbnails"),
            backups!,
            legacyBackups!,
        ] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Fixtures

    /// Skerry's artwork, cached in a folder a restart empties: the PNG is gone by now.
    private var skerryImageBlock: [String: Any] {
        Manager.makeImageWallpaperBlock(
            imageURL: root.appendingPathComponent("emptied by restart/atoll_artwork_wallpaper_1234.png")
        )
    }

    private var skerryAerialBlock: [String: Any] {
        Manager.makeAerialWallpaperBlock(assetID: Manager.customLiveWallpaperAssetID, existingBlock: nil)
    }

    private var userImageBlock: [String: Any] {
        Manager.makeImageWallpaperBlock(
            imageURL: URL(fileURLWithPath: "/System/Library/Desktop Pictures/Solid Colors/Stone.png")
        )
    }

    private var userAerialBlock: [String: Any] {
        Manager.makeAerialWallpaperBlock(assetID: "0E1C9B7A-6D2F-4C55-9E7B-3A0F1D2C4B6E", existingBlock: nil)
    }

    /// An Index.plist laid out the way the store keeps it and Skerry patches it: one
    /// block for every place, unless `override` puts another block in one place.
    private func indexPlist(
        _ block: [String: Any],
        override: (path: [String], block: [String: Any])? = nil
    ) -> [String: Any] {
        let entry: [String: Any] = ["Desktop": block, "Idle": block, "Type": "individual"]
        var plist: [String: Any] = [
            "AllSpacesAndDisplays": entry,
            "SystemDefault": entry,
            "Displays": ["Display-1": entry],
            "Spaces": ["Space-1": ["Default": entry, "Displays": ["Display-1": entry]]],
        ]
        if let override {
            plist = setting(override.block, at: override.path, in: plist)
        }
        return plist
    }

    private func setting(_ value: Any, at path: [String], in dictionary: [String: Any]) -> [String: Any] {
        var dictionary = dictionary
        guard let key = path.first else { return dictionary }
        if path.count == 1 {
            dictionary[key] = value
        } else {
            dictionary[key] = setting(value, at: Array(path.dropFirst()), in: dictionary[key] as? [String: Any] ?? [:])
        }
        return dictionary
    }

    @discardableResult
    private func write(_ plist: [String: Any], to url: URL) throws -> Data {
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        try data.write(to: url)
        return data
    }

    @discardableResult
    private func write(_ text: String, to url: URL) throws -> Data {
        let data = Data(text.utf8)
        try data.write(to: url)
        return data
    }

    private func contents(of url: URL) -> Data? {
        try? Data(contentsOf: url)
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private func recover(from folders: [URL]? = nil) {
        Manager.recoverWallpaper(store: store, backupFolders: folders ?? [backups, legacyBackups]) {
            restarts += 1
        }
    }

    // MARK: - Still Skerry's: the backup goes back

    func testSkerrysImageWallpaperIsReplacedByTheBackup() throws {
        try write(indexPlist(skerryImageBlock), to: index)
        let original = try write(indexPlist(userImageBlock), to: backups.appendingPathComponent(BackupName.plist))

        recover()

        XCTAssertEqual(contents(of: index), original)
        XCTAssertFalse(exists(backups.appendingPathComponent(BackupName.plist)))
        XCTAssertEqual(restarts, 1)
        let leftInStore = try FileManager.default.contentsOfDirectory(atPath: store.appendingPathComponent("Store").path)
        XCTAssertEqual(leftInStore, ["Index.plist"], "no staged copy is left next to the store")
    }

    func testSkerrysLiveWallpaperGetsEveryFileBack() throws {
        try write(indexPlist(skerryAerialBlock), to: index)
        try write("skerry manifest", to: manifest)
        try write("skerry video", to: video)
        try write("skerry thumbnail", to: thumbnail)
        let originalIndex = try write(indexPlist(userAerialBlock), to: backups.appendingPathComponent(BackupName.plist))
        let originalManifest = try write("original manifest", to: backups.appendingPathComponent(BackupName.manifest))
        let originalVideo = try write("original video", to: backups.appendingPathComponent(BackupName.video))
        let originalThumbnail = try write("original thumbnail", to: backups.appendingPathComponent(BackupName.thumbnail))

        recover()

        XCTAssertEqual(contents(of: index), originalIndex)
        XCTAssertEqual(contents(of: manifest), originalManifest)
        XCTAssertEqual(contents(of: video), originalVideo)
        XCTAssertEqual(contents(of: thumbnail), originalThumbnail)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: backups.path), [])
        XCTAssertEqual(restarts, 1)
    }

    func testTheTemporaryFolderOlderBuildsUsedIsRecoveredToo() throws {
        try write(indexPlist(skerryImageBlock), to: index)
        let original = try write(indexPlist(userImageBlock), to: legacyBackups.appendingPathComponent(BackupName.plist))

        recover()

        XCTAssertEqual(contents(of: index), original)
        XCTAssertFalse(exists(legacyBackups.appendingPathComponent(BackupName.plist)))
        XCTAssertEqual(restarts, 1)

        let folders = Manager.recoveryBackupFolders.map(\.standardizedFileURL)
        XCTAssertEqual(folders.first, Manager.backupFolder.standardizedFileURL)
        XCTAssertTrue(folders.contains(FileManager.default.temporaryDirectory.standardizedFileURL))
    }

    /// Every place the store keeps a wallpaper is looked at, Desktop and Idle alike;
    /// before, only a text search of the whole store was, and the asset id and the
    /// image URL sit in binary `Configuration` data it could not see into.
    func testSkerrysChoiceIsFoundInEveryPlaceOfTheStore() throws {
        let places: [[String]] = [
            ["AllSpacesAndDisplays"],
            ["Displays", "Display-1"],
            ["Spaces", "Space-1", "Default"],
            ["Spaces", "Space-1", "Displays", "Display-1"],
        ]
        for place in places {
            for name in ["Desktop", "Idle"] {
                for skerrys in [skerryImageBlock, skerryAerialBlock] {
                    try write(indexPlist(userImageBlock, override: (place + [name], skerrys)), to: index)
                    XCTAssertEqual(Manager.isSkerrysWallpaper(indexAt: index), true, "\(place + [name])")
                }
            }
        }
        try write(indexPlist(userAerialBlock), to: index)
        XCTAssertEqual(Manager.isSkerrysWallpaper(indexAt: index), false)
    }

    /// SystemDefault is what shows only while no other place holds a choice.
    func testSystemDefaultCountsWhenNothingElseIsSet() throws {
        try write(["SystemDefault": ["Desktop": skerryImageBlock, "Idle": skerryImageBlock, "Type": "individual"]], to: index)
        XCTAssertEqual(Manager.isSkerrysWallpaper(indexAt: index), true)
    }

    // MARK: - The user's own wallpaper: the backup is stale

    /// Skerry patched SystemDefault too; a wallpaper picked in System Settings after the
    /// crash leaves it as it was. The picked one is on screen and wins.
    func testAWallpaperPickedAfterTheCrashWinsOverSystemDefault() throws {
        let current = try write(indexPlist(userImageBlock, override: (["SystemDefault", "Desktop"], skerryImageBlock)), to: index)
        try write(indexPlist(userAerialBlock), to: backups.appendingPathComponent(BackupName.plist))

        recover()

        XCTAssertEqual(contents(of: index), current)
        XCTAssertFalse(exists(backups.appendingPathComponent(BackupName.plist)))
        XCTAssertEqual(restarts, 0)
    }

    func testAWallpaperTheUserChoseIsLeftAloneAndTheStaleBackupDropped() throws {
        let current = try write(indexPlist(userImageBlock), to: index)
        let currentManifest = try write("user manifest", to: manifest)
        try write(indexPlist(userAerialBlock), to: backups.appendingPathComponent(BackupName.plist))
        try write("old manifest", to: backups.appendingPathComponent(BackupName.manifest))

        recover()

        XCTAssertEqual(contents(of: index), current)
        XCTAssertEqual(contents(of: manifest), currentManifest)
        XCTAssertFalse(exists(backups.appendingPathComponent(BackupName.plist)))
        XCTAssertFalse(exists(backups.appendingPathComponent(BackupName.manifest)))
        XCTAssertEqual(restarts, 0)
    }

    func testNoBackupMeansNothingToDo() throws {
        let current = try write(indexPlist(skerryImageBlock), to: index)

        recover()

        XCTAssertEqual(contents(of: index), current)
        XCTAssertEqual(restarts, 0)
    }

    // MARK: - A store that cannot be read: undecided, the backup waits

    func testAnUnreadableStoreKeepsTheBackup() throws {
        let garbage = try write("not a property list", to: index)
        let backup = try write(indexPlist(userImageBlock), to: backups.appendingPathComponent(BackupName.plist))

        recover()

        XCTAssertNil(Manager.isSkerrysWallpaper(indexAt: index))
        XCTAssertEqual(contents(of: index), garbage)
        XCTAssertEqual(contents(of: backups.appendingPathComponent(BackupName.plist)), backup)
        XCTAssertEqual(restarts, 0)
    }

    func testAMissingStoreKeepsTheBackup() throws {
        let backup = try write(indexPlist(userImageBlock), to: backups.appendingPathComponent(BackupName.plist))

        recover()

        XCTAssertFalse(exists(index))
        XCTAssertEqual(contents(of: backups.appendingPathComponent(BackupName.plist)), backup)
        XCTAssertEqual(restarts, 0)
    }

    // MARK: - Restoring one file

    /// The current file used to be removed before the copy: a copy that failed left
    /// neither the wallpaper nor the backup in place.
    func testAFailedCopyLeavesTheCurrentFileInPlace() throws {
        let current = try write(indexPlist(skerryImageBlock), to: index)
        let unreadable = backups.appendingPathComponent(BackupName.plist)

        XCTAssertThrowsError(try Manager.restoreBackup(unreadable, to: index))

        XCTAssertEqual(contents(of: index), current)
    }

    func testABackupGoesInWhereNoFileIsLeft() throws {
        let backupURL = backups.appendingPathComponent(BackupName.video)
        let backup = try write("original video", to: backupURL)

        try Manager.restoreBackup(backupURL, to: video)

        XCTAssertEqual(contents(of: video), backup)
        XCTAssertFalse(exists(backupURL))
    }
}
