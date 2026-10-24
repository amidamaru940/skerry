"""Every call that makes macOS ask the person at the Mac for a permission
sits behind AppRuntimeEnvironment.mayAskForPermissions, so the unit-test
host never asks: to macOS it is an app of its own, and it asked again on
every test run."""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "DynamicIsland"

# Calls that bring up a system permission prompt.
PROMPTS = [
    r"AXIsProcessTrustedWithOptions\(",
    r"calendarService\.requestAccess\(",
    r"CBCentralManager\(delegate",
    r"CBCentralManager\($",
    r"BluetoothAuthorizationRequest \{",
    r"setupBluetoothObservers\(\)$",
    r"open\(path, O_EVTONLY\)",
    r"contentsOfDirectory\(at: downloadsDirectory",
    r"Self\.sample\(in: downloadsDirectory",
    r"contentsOfDirectory\(at: documentsDirectory",
    r"ProtectedFolder\.touch\(",
    r"check\(askingUser: true\)",
]
GUARD = "AppRuntimeEnvironment.mayAskForPermissions"
WINDOW = 20  # lines above the call that may hold the guard (the top of its function)


def enclosing_function(lines, number):
    """The name of the func that line `number` sits in."""
    enclosing = next(l for l in reversed(lines[:number + 1]) if re.search(r"\bfunc \w+\(", l))
    return re.search(r"func (\w+)\(", enclosing).group(1)


def function_body(source, name):
    """The text between the braces of `func name(`."""
    start = source.index("{", source.index(f"func {name}("))
    depth = 0
    for index in range(start, len(source)):
        depth += {"{": 1, "}": -1}.get(source[index], 0)
        if depth == 0:
            return source[start:index + 1]
    raise ValueError(name)


class PermissionPromptTests(unittest.TestCase):
    def test_every_prompt_is_guarded(self):
        unguarded, found = [], 0
        for path in sorted(SOURCES.rglob("*.swift")):
            lines = path.read_text(encoding="utf-8").splitlines()
            for number, line in enumerate(lines):
                code = line.split("//", 1)[0]
                if any(re.search(p, code) for p in PROMPTS):
                    found += 1
                    above = "\n".join(lines[max(0, number - WINDOW):number])
                    if GUARD not in above:
                        unguarded.append(f"{path.relative_to(ROOT)}:{number + 1}")
        self.assertGreaterEqual(found, 5, "the scan must see the prompts it guards")
        self.assertEqual(unguarded, [])

    def test_bluetooth_is_asked_only_from_a_click(self):
        """§5.8: launch only reads the Bluetooth authorization. The question is
        built in requestBatteryAccess() alone, and only views call that: no
        manager and nothing in the app's launch code."""
        manager = SOURCES / "managers" / "BluetoothAudioManager.swift"
        lines = manager.read_text(encoding="utf-8").splitlines()
        builders = []
        for number, line in enumerate(lines):
            if re.search(r"BluetoothAuthorizationRequest \{", line.split("//", 1)[0]):
                enclosing = next(l for l in reversed(lines[:number]) if re.search(r"\bfunc \w+\(", l))
                builders.append(re.search(r"func (\w+)\(", enclosing).group(1))
        self.assertEqual(builders, ["requestBatteryAccess"])

        callers = []
        for path in sorted(SOURCES.rglob("*.swift")):
            for number, line in enumerate(path.read_text(encoding="utf-8").splitlines()):
                code = line.split("//", 1)[0]
                if "requestBatteryAccess()" in code and "func requestBatteryAccess" not in code:
                    callers.append(str(path.relative_to(SOURCES)))
        self.assertTrue(callers, "the Settings toggles call it")
        launch = [c for c in callers if c.startswith("managers/") or c == "DynamicIslandApp.swift"]
        self.assertEqual(launch, [])

    def test_iobluetooth_and_the_battery_reader_wait_for_bluetooth(self):
        """IOBluetooth's first use waits for the Bluetooth answer (a frozen
        island at launch, 21.10) and a CBCentralManager asks the question, so
        both run only once Bluetooth is allowed."""
        calls = [
            r"IOBluetoothDevice\.pairedDevices\(",
            r"IOBluetoothDevice\.register\(",
            r"IOBluetoothHostController\.default\(",
        ]
        unguarded, found = [], 0
        for path in sorted(SOURCES.rglob("*.swift")):
            lines = path.read_text(encoding="utf-8").splitlines()
            for number, line in enumerate(lines):
                if any(re.search(p, line.split("//", 1)[0]) for p in calls):
                    found += 1
                    if "bluetoothAllowed" not in "\n".join(lines[max(0, number - WINDOW):number]):
                        unguarded.append(f"{path.relative_to(ROOT)}:{number + 1}")
        self.assertGreaterEqual(found, 5, "the scan must see the calls it guards")
        self.assertEqual(unguarded, [])

        # The BLE reader's manager is made by its start() alone, and only the
        # Bluetooth watch starts it: every way in has just seen .allowedAlways
        # or the person's yes, so the reader reads no authorization itself.
        lines = (SOURCES / "managers" / "BluetoothAudioManager.swift").read_text(encoding="utf-8").splitlines()
        def callers(pattern):
            found = []
            for number, line in enumerate(lines):
                if re.search(pattern, line.split("//", 1)[0]):
                    enclosing = next(l for l in reversed(lines[:number]) if re.search(r"\bfunc \w+\(", l))
                    found.append(re.search(r"func (\w+)\(", enclosing).group(1))
            return found
        self.assertEqual(callers(r"CBCentralManager\(delegate: self, queue: nil\)"), ["start"])
        self.assertEqual(callers(r"batteryReader\.start\(\)"), ["startBluetoothWatch"])

    def test_the_main_thread_reads_no_new_bluetooth_authorization(self):
        """CBManager.authorization is a TCC preflight, an XPC call to tccd.
        The CoreAudio reports carry it, read on the observer's queue; the
        battery refresh (every connect, disconnect and lock-screen refresh)
        and the start of the Bluetooth watch go by the stored watch."""
        source = (SOURCES / "managers" / "BluetoothAudioManager.swift").read_text(encoding="utf-8")
        for name in ["applyAudioRouteReport", "refreshBatteryLevelsForConnectedDevices", "startBluetoothWatch"]:
            body = function_body(source, name)
            self.assertNotIn("CBManager.authorization", body, name)
            self.assertNotIn("bluetoothAllowed", body, name)
        observer = (SOURCES / "managers" / "BluetoothAudioRouteObserver.swift").read_text(encoding="utf-8")
        self.assertIn("CBManager.authorization", function_body(observer, "report"))

    def test_music_and_spotify_are_scripted_only_after_the_automation_check(self):
        """§5.8: an Apple Event to an app macOS has no answer for asks. Every
        function that scripts Music or Spotify checks AutomationConsent first,
        and the reads nobody clicked for use the check that never asks."""
        files = [
            "MediaControllers/AppleMusicController.swift",
            "MediaControllers/SpotifyController.swift",
            "managers/AppleMusicAirPlayManager.swift",
        ]
        unchecked, senders = [], {}
        for name in files:
            lines = (SOURCES / name).read_text(encoding="utf-8").splitlines()
            for number, line in enumerate(lines):
                if "AppleScriptHelper.execute" not in line.split("//", 1)[0]:
                    continue
                start = next(i for i in range(number, -1, -1) if re.search(r"\bfunc \w+\(", lines[i]))
                body = "\n".join(lines[start:number])
                senders[re.search(r"func (\w+)\(", lines[start]).group(1)] = body
                if "AutomationConsent." not in body:
                    unchecked.append(f"{name}:{number + 1}")
        self.assertGreaterEqual(len(senders), 8, "the scan must see the senders it checks")
        self.assertEqual(unchecked, [])
        for read in ["fetchPlaybackInfoDescriptor", "fetchSpotifyPlaybackInfo", "isCurrentTrackFavorited"]:
            self.assertIn("allowsUnclickedEvent()", senders[read], read)

    def test_only_a_click_reads_through_the_check_that_may_ask(self):
        """§5.8: a read that may ask (`afterClick: true`) runs only after a
        click: the AirPlay buttons, or refreshAfterClick(), which Auto calls
        from its controls and MusicManager when a source is chosen in
        Settings or «Open player» opens it."""
        reads = []
        for path in sorted(SOURCES.rglob("*.swift")):
            lines = path.read_text(encoding="utf-8").splitlines()
            relative = str(path.relative_to(SOURCES))
            for number, line in enumerate(lines):
                if "afterClick: true" in line.split("//", 1)[0]:
                    reads.append((relative, enclosing_function(lines, number)))
        self.assertTrue(reads, "the scan must see the reads it checks")
        stray = [r for r in reads if not (r[0].startswith("components/") or r[1].endswith("AfterClick"))]
        self.assertEqual(stray, [])

        def callers(call):
            found = {}
            for path in sorted(SOURCES.rglob("*.swift")):
                lines = path.read_text(encoding="utf-8").splitlines()
                for number, line in enumerate(lines):
                    code = line.split("//", 1)[0]
                    if call in code and f"func {call}" not in code:
                        found.setdefault(str(path.relative_to(SOURCES)), set()).add(enclosing_function(lines, number))
            return found

        self.assertEqual(callers("refreshAfterClick("), {
            "MediaControllers/AutoMediaController.swift": {"askAboutPlayerAfterClick"},
            "managers/MusicManager.swift": {"readScriptedPlayerAfterClick"},
        })
        controls = {"play", "pause", "seek", "nextTrack", "previousTrack", "togglePlay",
                    "toggleShuffle", "toggleRepeat", "setCurrentTrackFavorited"}
        self.assertEqual(callers("askAboutPlayerAfterClick("),
                         {"MediaControllers/AutoMediaController.swift": controls})
        self.assertEqual(callers("readScriptedPlayerAfterClick("),
                         {"managers/MusicManager.swift": {"mediaSourceChosen", "openMusicApp"}})
        posts = [c for c in callers("name: Notification.Name.mediaControllerChanged") if not c.startswith("components/")]
        self.assertEqual(posts, [], "only the source picker in Settings says a source was chosen")

    def test_protected_folders_are_first_touched_only_after_the_person_asked(self):
        """§5.8: a fresh install is asked for the screenshot folder and for
        Downloads only once the person asked for screenshots or downloads.
        Launch touches no folder itself; startAtLaunch() looks at a folder
        only with its stored first-touch flag set, given to an earlier
        install by the migration that runs first; every other first touch
        starts from a view or from the download switch. setWatching() looks
        at a moved screenshot folder, which only a started manager does."""
        app = (SOURCES / "DynamicIslandApp.swift").read_text(encoding="utf-8")
        launch = function_body(app, "applicationDidFinishLaunching")
        self.assertFalse("ProtectedFolder.touch(" in launch, "applicationDidFinishLaunching touches a folder itself")
        self.assertLess(launch.index("migrateFolderFirstTouch()"), launch.index(".startAtLaunch()"))

        touches = {}
        for path in sorted(SOURCES.rglob("*.swift")):
            lines = path.read_text(encoding="utf-8").splitlines()
            for number, line in enumerate(lines):
                if "ProtectedFolder.touch(" in line.split("//", 1)[0]:
                    touches.setdefault(str(path.relative_to(SOURCES)), []).append(enclosing_function(lines, number))
        self.assertEqual(touches, {
            "components/Screenshots/ScreenshotShelfManager.swift": ["lookAtFolderThenStart", "setWatching"],
            "managers/DownloadManager.swift": ["startAtLaunch", "listenerSettingChanged"],
        })
        for name, flag in [
            ("components/Screenshots/ScreenshotShelfManager.swift", "Defaults[.screenshotFolderTouched]"),
            ("managers/DownloadManager.swift", "Defaults[.downloadsFolderTouched]"),
        ]:
            self.assertIn(flag, function_body((SOURCES / name).read_text(encoding="utf-8"), "startAtLaunch"), name)
        shelf = (SOURCES / "components/Screenshots/ScreenshotShelfManager.swift").read_text(encoding="utf-8")
        self.assertIn("guard started", function_body(shelf, "refreshFolder"))
        self.assertIn("guard started", function_body(shelf, "refreshFolderLocation"))
        # Before start only the setting is re-read: Settings shows where
        # screenshots go, and the folder itself is not looked at.
        self.assertRegex(function_body(shelf, "refreshFolder"),
                         r"guard started else \{\s*folder = ScreenshotLocation\.current\(\)\s*return\s*\}")

        # The screenshot flag holds for the folder macOS answered for: launch
        # does not look at a folder that moved while Skerry was not running.
        self.assertIn("Defaults[.screenshotFolderTouchedPath]", function_body(shelf, "startAtLaunch"))
        self.assertIn("launchLooksAtScreenshotFolder(", function_body(shelf, "startAtLaunch"))
        for name in ["lookAtFolderThenStart", "setWatching"]:
            self.assertIn("Self.noteAnswered(", function_body(shelf, name), name)
        self.assertIn("Defaults[.screenshotFolderTouchedPath] =", function_body(shelf, "noteAnswered"))

        callers = []
        for path in sorted(SOURCES.rglob("*.swift")):
            for line in path.read_text(encoding="utf-8").splitlines():
                code = line.split("//", 1)[0]
                if "startOnFirstUse()" in code and "func startOnFirstUse" not in code:
                    callers.append(str(path.relative_to(SOURCES)))
        self.assertTrue(callers, "onboarding, the Screenshots segment and Settings call it")
        self.assertTrue(all(c.startswith("components/") for c in callers), callers)

    def test_the_folder_migration_reads_only_what_the_app_stored(self):
        """Each Defaults.Key registers its default at its first use, and the
        merged view (UserDefaults.standard.object(forKey:)) hands that back
        as if stored: read that way, every fresh install looked like an
        earlier one and was asked for the Desktop and Downloads at launch.
        The traces come from the app's own persistent domain, and an earlier
        install gets the screenshot flag for any folder."""
        constants = (SOURCES / "models/Constants.swift").read_text(encoding="utf-8")
        migration = function_body(constants, "migrateFolderFirstTouch")
        self.assertNotRegex(migration, r"UserDefaults\.standard\.\w+\(forKey:")
        self.assertNotRegex(migration, r"Defaults\[\.(onboardingCompleted|onboardingStep|enableScreenshotShelf|collectClipboardScreenshots)\]")
        self.assertIn("FolderFirstTouch.launchedBefore(", migration)
        self.assertIn("Defaults[.screenshotFolderTouchedPath] = FolderFirstTouch.anyScreenshotFolder", migration)

        lines = (SOURCES / "helpers/ProtectedFolder.swift").read_text(encoding="utf-8").splitlines()
        code = [line.split("//", 1)[0] for line in lines]
        readers = [enclosing_function(lines, n) for n, line in enumerate(code) if "persistentDomain(forName:" in line]
        self.assertEqual(readers, ["launchedBefore"])
        self.assertFalse([line for line in code if re.search(r"\.(object|bool|string)\(forKey:", line)])

    def test_folder_rows_read_a_folder_only_once_it_was_asked_for(self):
        """§5.8, "unknown until asked": Shelf settings read Documents and
        Downloads to fill their rows only once the folder's first-touch flag
        is set. Before that, the read would be the macOS prompt."""
        unguarded, found = [], 0
        for path in sorted(SOURCES.rglob("*.swift")):
            lines = path.read_text(encoding="utf-8").splitlines()
            for number, line in enumerate(lines):
                if re.search(r"ShelfFolderAccessAuthorization\.has\w*Access\(", line.split("//", 1)[0]):
                    found += 1
                    if "FolderTouched]" not in "\n".join(lines[max(0, number - 6):number + 1]):
                        unguarded.append(f"{path.relative_to(ROOT)}:{number + 1}")
        self.assertGreaterEqual(found, 2, "the scan must see the reads it guards")
        self.assertEqual(unguarded, [])

    def test_launch_recovery_runs_only_through_its_gate(self):
        """SIGCONT and the wallpaper recovery must not run in the test host or beside
        another Skerry: they would undo what the running copy froze on purpose."""
        source = (SOURCES / "DynamicIslandApp.swift").read_text(encoding="utf-8")
        lines = source.splitlines()
        calls = [n for n, l in enumerate(lines) if "recoverAfterUncleanExit()" in l or 'continueProcesses(named: ["OSDUIHelper"])' in l]
        self.assertEqual(len(calls), 2, "the scan must see both launch-recovery calls")
        for n in calls:
            above = "\n".join(lines[max(0, n - 6):n])
            self.assertIn("if LaunchRecoveryGate.recoversAtThisLaunch", above, f"DynamicIslandApp.swift:{n + 1}")

    def test_the_screen_assistant_keychain_never_asks(self):
        """R2c: the API keys move into the login Keychain at launch. Every
        SecItem call there carries a context that may not ask, so a call that
        would need a window fails with a status instead. The data protection
        Keychain is not used (no provisioning profile: -34018), and the test
        host never runs the migration, which would write to the real Keychain."""
        store = (SOURCES / "managers" / "ScreenAssistantKeyStore.swift").read_text(encoding="utf-8")
        self.assertNotIn("kSecUseDataProtectionKeychain", store)
        query = function_body(store, "query")
        self.assertIn("interactionNotAllowed = true", query)
        self.assertIn("kSecUseAuthenticationContext as String: context", query)
        self.assertIn("kSecAttrSynchronizable as String: false", query)

        # Each call's dictionary is built from that query in its own function.
        lines = store.splitlines()
        calls = [n for n, line in enumerate(lines) if re.search(r"\bSecItem\w+\(", line.split("//", 1)[0])]
        self.assertEqual(len(calls), 5, "the scan must see the store's SecItem calls")
        names = set()
        for number in calls:
            start = next(i for i in range(number, -1, -1) if re.search(r"\bfunc \w+\(", lines[i]))
            names.add(re.search(r"func (\w+)\(", lines[start]).group(1))
            self.assertIn("query(for: account)", "\n".join(lines[start:number + 1]), f"line {number + 1}")
        self.assertEqual(names, {"read", "contains", "write", "delete"})

        # Whether a key is saved comes from its attributes: no secret decrypted.
        keychain = store[store.index("struct KeychainScreenAssistantKeyStore"):]
        contains = function_body(keychain, "contains")
        self.assertIn("kSecReturnAttributes as String] = true", contains)
        self.assertIn("kSecMatchLimitOne", contains)
        self.assertNotIn("kSecReturnData", contains)

        app = (SOURCES / "DynamicIslandApp.swift").read_text(encoding="utf-8")
        launch = function_body(app, "applicationDidFinishLaunching")
        self.assertRegex(launch, r"if !AppRuntimeEnvironment\.isHostingUnitTests \{\s*ScreenAssistantKeys\.migrateAtLaunch\(\)\s*\}")
        self.assertIn("queue.async", function_body(store, "migrateAtLaunch"), "the migration runs off the main thread")
        tests = ROOT / "DynamicIslandTests"
        for path in sorted(tests.rglob("*.swift")):
            text = path.read_text(encoding="utf-8")
            self.assertNotIn("ScreenAssistantKeys.", text, path.name)
            self.assertNotRegex(text, r"KeychainScreenAssistantKeyStore\([^)]*\)\.(read|contains|write|delete)\(", path.name)
            self.assertNotRegex(text, r"store:\s*KeychainScreenAssistantKeyStore\(", path.name)

    def test_screen_recording_is_asked_only_from_the_snip_button(self):
        """R2c, item 8: the Screen Assistant never calls
        CGRequestScreenCaptureAccess; macOS asks for Screen Recording when
        /usr/sbin/screencapture first runs. That process starts in one place,
        and the only way there is the person pressing the snip button or
        picking a snip type in its popover."""
        launched = []
        for path in sorted(SOURCES.rglob("*.swift")):
            lines = path.read_text(encoding="utf-8").splitlines()
            for number, line in enumerate(lines):
                if "/usr/sbin/screencapture" in line.split("//", 1)[0]:
                    launched.append((path.name, enclosing_function(lines, number)))
        self.assertEqual(launched, [("ScreenshotSnippingTool.swift", "takeScreenshot")])

        tool = (SOURCES / "components" / "ScreenAssistant" / "ScreenshotSnippingTool.swift").read_text(encoding="utf-8")
        tool_lines = tool.splitlines()
        self.assertRegex(tool, r"private func takeScreenshot\(")
        takers = [enclosing_function(tool_lines, n) for n, line in enumerate(tool_lines)
                  if re.search(r"\btakeScreenshot\(", line.split("//", 1)[0]) and "func takeScreenshot(" not in line]
        self.assertEqual(takers, ["startSnipping"])

        # Every way into startSnipping from outside the tool.
        entry = re.compile(r"\.(startSnipping|startAreaScreenshot|startFullScreenshot|startWindowScreenshot)\(")
        callers = []
        for path in sorted(SOURCES.rglob("*.swift")):
            if path.name == "ScreenshotSnippingTool.swift":
                continue
            lines = path.read_text(encoding="utf-8").splitlines()
            for number, line in enumerate(lines):
                if entry.search(line.split("//", 1)[0]):
                    callers.append((path.name, enclosing_function(lines, number)))
        self.assertEqual(callers, [("ChatPanels.swift", "startScreenshot")])

        # startScreenshot runs from the button's action and from the popover's
        # choice, and from nothing else.
        panels = (SOURCES / "components" / "ScreenAssistant" / "ChatPanels.swift").read_text(encoding="utf-8")
        button = panels[panels.index("struct ScreenshotButton: View"):panels.index("struct ChatPanelsVisualEffectView")]
        uses = [line.strip() for line in button.splitlines()
                if re.search(r"\bstartScreenshot\(|\bstartQuickScreenshot\b", line.split("//", 1)[0])
                and not re.search(r"func (startScreenshot|startQuickScreenshot)\(", line)]
        self.assertEqual(uses, [
            "Button(action: startQuickScreenshot) {",
            "startScreenshot(type: type)",
            "startScreenshot(type: .area)",
        ])
        self.assertIn("ScreenshotOptionsPopover { type in\n                    startScreenshot(type: type)", button)
        self.assertIn("private func startQuickScreenshot() {\n        // Default to area screenshot for quick action\n        startScreenshot(type: .area)", button)
        self.assertEqual(panels.count("startScreenshot("), button.count("startScreenshot("), "startScreenshot used outside the button")

    def test_the_test_host_is_never_allowed_to_ask(self):
        source = (SOURCES / "helpers" / "AppRuntimeEnvironment.swift").read_text()
        self.assertIn("mayAskForPermissions: Bool = !isUITesting && !isHostingUnitTests", source)


if __name__ == "__main__":
    unittest.main()
