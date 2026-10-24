"""Energy rules from docs/perf/REPORT-energy.md, checked in the source.

The overheating of 17.10 came from work that ran on its own clock while the
Mac sat idle or slept: a looping idle animation, two `log stream` processes,
pollers from launch, a 2 Hz loop for the whole lock. These tests keep each
of them from coming back. They read the code, so they run anywhere (CI has
no Xcode test run).
"""

import re
import stat
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "DynamicIsland"


def source(relative):
    return (APP / relative).read_text()


def swift_files():
    return sorted(APP.rglob("*.swift"))


def without_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


class SleepAndAssertionTests(unittest.TestCase):
    def test_only_keep_awake_holds_a_power_assertion(self):
        holders = [p.relative_to(APP).as_posix() for p in swift_files()
                   if "IOPMAssertionCreate" in without_comments(p.read_text())]
        self.assertEqual(["managers/CaffeinateManager.swift"], holders)

    def test_no_activity_keeps_the_mac_or_app_awake(self):
        for path in swift_files():
            code = without_comments(path.read_text())
            for banned in ("beginActivity(", "performActivity(", "idleSystemSleepDisabled",
                           "disableAutomaticTermination", "NSAppSleepDisabled"):
                self.assertNotIn(banned, code, f"{path.relative_to(APP)}: {banned}")
        info = (APP / "Info.plist").read_text()
        self.assertNotIn("NSAppSleepDisabled", info)

    def test_the_gate_hears_every_sleep_screen_lock_and_session_notice(self):
        gate = source("helpers/ActivityGate.swift")
        for name in ("willSleepNotification", "didWakeNotification", "screensDidSleepNotification",
                     "screensDidWakeNotification", "sessionDidResignActiveNotification",
                     "sessionDidBecomeActiveNotification", "com.apple.screenIsLocked",
                     "com.apple.screenIsUnlocked"):
            self.assertIn(name, gate)

    def test_the_gate_exists_from_launch(self):
        self.assertIn("_ = ActivityGate.shared", source("DynamicIslandApp.swift"))

    def test_there_is_a_will_sleep_test(self):
        tests = (ROOT / "DynamicIslandTests" / "EnergyTests.swift").read_text()
        self.assertIn("func testOnWillSleepEverythingIsStopped", tests)
        project = (ROOT / "DynamicIsland.xcodeproj" / "project.pbxproj").read_text()
        self.assertIn("EnergyTests.swift in Sources", project)


class PollingTests(unittest.TestCase):
    def test_the_clipboard_is_looked_at_once_a_second_with_tolerance(self):
        watcher = source("managers/ClipboardChangeWatcher.swift")
        interval = float(re.search(r"static let interval: TimeInterval = ([\d.]+)", watcher).group(1))
        tolerance = float(re.search(r"static let tolerance: TimeInterval = ([\d.]+)", watcher).group(1))
        self.assertGreaterEqual(interval, 1)
        self.assertGreaterEqual(tolerance, 0.5)
        self.assertIn("idleAfter", watcher, "the look pauses without input")
        clipboard = without_comments(source("managers/ClipboardManager.swift"))
        self.assertNotIn("scheduledTimer(withTimeInterval: 0.5", clipboard)
        self.assertNotIn("scheduledTimer(withTimeInterval: 60, repeats: true", clipboard,
                         "expiry is one timer for the next due item")
        self.assertIn("ClipboardChangeWatcher.shared.add", clipboard)

    def test_the_clipboard_screenshot_collector_has_no_timer_of_its_own(self):
        collector = without_comments(source("components/Screenshots/ClipboardScreenshotCollector.swift"))
        self.assertNotIn("Timer(", collector)
        self.assertIn("watcher.add", collector)

    def test_no_poll_while_locked(self):
        lock = without_comments(source("managers/LockScreenManager.swift"))
        self.assertNotIn("while !Task.isCancelled", lock, "the 2 Hz lock loop")
        self.assertIn("screensDidWakeNotification", lock)

    def test_menu_bar_clearance_has_no_timer(self):
        layout = without_comments(source("managers/MenuBarLayout.swift"))
        self.assertNotIn("Timer(", layout)
        self.assertNotIn("scheduledTimer", layout)

    def test_screenshots_have_no_rescan_timer(self):
        shelf = without_comments(source("components/Screenshots/ScreenshotShelfManager.swift"))
        self.assertNotIn("scheduledTimer", shelf)

    def test_bluetooth_is_event_driven(self):
        bluetooth = without_comments(source("managers/BluetoothAudioManager.swift"))
        self.assertNotIn("withTimeInterval: 3.0", bluetooth)
        self.assertNotIn("name: nil", bluetooth, "observing every distributed notification")
        self.assertIn("register(\n            forConnectNotifications", bluetooth)

    def test_focus_is_watched_not_polled(self):
        focus = without_comments(source("managers/DoNotDisturbManager.swift"))
        self.assertNotIn("makeTimerSource", focus)
        self.assertNotIn("repeating: .seconds(2)", focus)

    def test_memory_and_hover_have_no_idle_loop(self):
        memory = without_comments(source("managers/MemoryUsageMonitor.swift"))
        self.assertNotIn("Task.sleep", memory)
        content = without_comments(source("ContentView.swift"))
        self.assertNotIn("hiddenEdgeHoverPollingIntervalMs", content)
        self.assertIn("while !Task.isCancelled, self.isHovering", content)

    def test_pointer_moves_are_watched_only_for_hide_until_hover(self):
        # The hover ears took every pointer move of the session: 2.4-2.8 % CPU
        # with the mouse moving, 0.07 % without (REPORT-energy.md §9).
        content = without_comments(source("ContentView.swift"))
        self.assertEqual(1, content.count("addGlobalMonitorForEvents(matching: [.mouseMoved])"))
        wants = re.search(r"var wantsHiddenIslandPointerMonitor: Bool \{(.*?)\n    \}", content, re.S).group(1)
        self.assertIn("shouldHideUntilHover", wants)
        self.assertNotIn("openNotchOnHover", wants)
        self.assertNotIn("IslandHoverZone.zone", content)

    def test_the_os_helper_watcher_stops_when_quiet(self):
        osd = source("managers/SystemOSDManager.swift")
        self.assertIn("watcherQuietChecks", osd)

    def test_brightness_polls_only_after_a_key(self):
        controllers = source("managers/SystemMediaControllers.swift")
        self.assertIn("pollsAfterKeyPresses = !coreBrightnessClient.isAvailable", controllers)


class ProcessTests(unittest.TestCase):
    def test_log_streams_run_only_on_demand(self):
        bridge = without_comments(source("managers/SystemTimerBridge.swift"))
        calls = [m.start() for m in re.finditer(r"startLogStream\(\)", bridge)]
        definition = bridge.index("private func startLogStream() -> Bool")
        callers = [c for c in calls if abs(c - definition) > 40]
        self.assertTrue(callers)
        for call in callers:
            before = bridge[:call]
            enclosing = before[before.rindex("func "):]
            self.assertTrue("updateLogStreamDemand" in enclosing.splitlines()[0]
                            or "wantsLogStream" in enclosing,
                            "the log stream starts only when a timer is there to follow")
        airpods = without_comments(source("managers/BluetoothAudioManager.swift"))
        self.assertIn("hasAirPods && enabled && present", airpods)

    def test_every_pipe_reader_stops_at_end_of_file(self):
        for path in swift_files():
            code = path.read_text()
            for match in re.finditer(r"readabilityHandler = \{", code):
                block = code[match.end():match.end() + 700]
                if "availableData" not in block:
                    continue
                self.assertIn("readabilityHandler = nil", block,
                              f"{path.relative_to(APP)}: a handler left installed at EOF runs for ever")

    def test_the_now_playing_adapter_starts_from_audio_output(self):
        controller = without_comments(source("MediaControllers/NowPlayingController.swift"))
        init = controller[controller.index("init?()"):controller.index("private func beginWatchingForPlayers")]
        self.assertNotIn("setupNowPlayingObserver", init, "no adapter at launch")
        self.assertIn("onOutputStarted", controller)
        self.assertIn("idleGrace", controller)
        self.assertIn("publisher(for: .screenInUse)", controller)
        self.assertNotIn("await self?.processJSONStream()", controller, "the task kept the controller alive")

    def test_listeners_of_gone_audio_processes_are_not_removed(self):
        # 24.10: removing them only logged "no object with given ID" each
        # time an app stopped playing.
        activity = without_comments(source("audio/AudioOutputActivity.swift"))
        sync = activity[activity.index("func syncProcesses()"):activity.index("private func removeProcessListener")]
        self.assertNotIn("removeProcessListener(", sync)
        stop = activity[activity.index("func stop()"):activity.index("func syncProcesses()")]
        self.assertIn("where present.contains(object)", stop)


class AnimationTests(unittest.TestCase):
    def test_the_idle_animation_does_not_loop_for_ever(self):
        idle = without_comments(source("components/IdleAnimationView.swift"))
        self.assertNotIn("LUStateData", idle)
        self.assertIn("PausableLottieView", idle)
        self.assertIn("IdleAnimationPlayback.performance", idle)

    def test_the_wing_visualizer_pauses_with_the_music(self):
        wing = without_comments(source("components/Music/LottieAnimationView.swift"))
        self.assertNotIn("LUStateData", wing)
        self.assertIn("isPlaying: isPlaying", wing)

    def test_marquee_loops_do_not_stack(self):
        marquee = source("components/Live activities/MarqueeTextView.swift")
        self.assertIn("generation == loopGeneration", marquee)


class NetworkTests(unittest.TestCase):
    def test_no_peer_to_peer_wifi(self):
        for path in swift_files():
            self.assertNotIn("includePeerToPeer = true", without_comments(path.read_text()),
                             str(path.relative_to(APP)))

    def test_listeners_are_loopback_or_paused_while_away(self):
        for path in swift_files():
            code = without_comments(path.read_text())
            if "NWListener(" not in code:
                continue
            rel = path.relative_to(APP).as_posix()
            if rel == "services/Extensions/ExtensionRPCServer.swift":
                self.assertIn("requiredLocalEndpoint", code)
            else:
                self.assertEqual("components/Shelf/Services/LocalSendService.swift", rel)
                self.assertIn("ActivityGate.shared.publisher(for: .userPresent)", code)

    def test_the_route_watch_pauses_while_away(self):
        network = without_comments(source("managers/NetworkConnectivityManager.swift"))
        self.assertIn("ActivityGate.shared.publisher(for: .userPresent)", network)

    def test_the_battery_reader_lets_go_of_every_connection_it_opens(self):
        # 24.10: a battery read that timed out left its LE connect request
        # pending in bluetoothd for as long as Skerry ran, and a finished one
        # kept its link, beside the LE traffic Handoff and Universal
        # Clipboard need.
        manager = without_comments(source("managers/BluetoothAudioManager.swift"))
        reader = manager[manager.index("class BluetoothLEBatteryReader"):manager.index("struct BluetoothAudioDevice")]

        def body(signature):
            start = reader.index(signature)
            return reader[start:reader.index("\n    }\n", start)]

        self.assertEqual(1, reader.count("central.connect("), "one place connects")
        self.assertNotIn("EnableAutoReconnect", reader)
        configure = body("func configurePeripheral(")
        self.assertLess(configure.index("openedPeripherals[peripheral.identifier] = peripheral"),
                        configure.index("central.connect("))
        self.assertIn("central.cancelPeripheralConnection(peripheral)", body("func releasePeripheral("))
        self.assertIn("releasePeripheral(identifier)", body("func complete("), "timeout and the end of a read")
        self.assertIn("releasePeripheral(identifier)", body("func markPeripheralFinished("))
        self.assertIn("central.cancelPeripheralConnection(peripheral)",
                      body("didConnect peripheral: CBPeripheral)"), "a late connection is let go")


class ScriptTests(unittest.TestCase):
    def test_measurement_scripts_are_short_and_executable(self):
        for name in ("measure.sh", "bisect-step.sh"):
            path = ROOT / "scripts" / "perf" / name
            self.assertTrue(path.exists(), name)
            self.assertTrue(path.stat().st_mode & stat.S_IXUSR, f"{name} is not executable")
        measure = (ROOT / "scripts" / "perf" / "measure.sh").read_text()
        self.assertIn("SECONDS_TOTAL > 180", measure, "a run never lasts more than 3 minutes")


if __name__ == "__main__":
    unittest.main()
