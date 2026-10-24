import plistlib
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "DynamicIsland"
ENTITLEMENTS = ROOT / "DynamicIsland" / "DynamicIsland.entitlements"
PROJECT = ROOT / "DynamicIsland.xcodeproj" / "project.pbxproj"
RELEASE_SCRIPT = ROOT / "scripts" / "make-release.sh"
CI_WORKFLOW = ROOT / ".github" / "workflows" / "ci.yml"


class PrivacyConfigurationTests(unittest.TestCase):
    def test_camera_capture_is_not_entitled(self):
        entitlements = plistlib.loads(ENTITLEMENTS.read_bytes())

        self.assertNotIn("com.apple.security.device.camera", entitlements)

    def test_notes_sync_is_authorized_for_apple_events(self):
        project = PROJECT.read_text()
        entitlements = plistlib.loads(ENTITLEMENTS.read_bytes())

        self.assertNotIn("AUTOMATION_APPLE_EVENTS = NO;", project)
        self.assertIn(
            "com.apple.Notes",
            entitlements["com.apple.security.temporary-exception.apple-events"],
        )

    def test_automation_usage_text_names_notes(self):
        project = PROJECT.read_text()

        self.assertEqual(
            2,
            project.count(
                'INFOPLIST_KEY_NSAppleEventsUsageDescription = "Skerry uses AppleScripts to control Spotify, Apple Music, and Notes.";'
            ),
        )

    def test_full_access_reminder_api_has_matching_usage_text(self):
        project = PROJECT.read_text()

        self.assertEqual(
            2,
            project.count("INFOPLIST_KEY_NSRemindersFullAccessUsageDescription ="),
        )

    def test_release_keeps_the_app_entitlements(self):
        # Upstream checked this in its release workflow, which re-signed the
        # archive with Developer ID; Skerry releases with scripts/make-release.sh,
        # which signs once, ad hoc, and checks the result itself.
        script = RELEASE_SCRIPT.read_text()

        self.assertIn('codesign -d --entitlements :- "$APP"', script)
        self.assertIn('*"com.apple.security.automation.apple-events"*', script)
        self.assertIn('!= *"com.apple.security.device.camera"*', script)
        self.assertNotIn("codesign --force", script, "no re-signing that could drop entitlements")

    def test_ci_checks_the_privacy_configuration(self):
        workflow = CI_WORKFLOW.read_text()

        self.assertIn("python3 -m unittest tests.test_privacy_configuration", workflow)


    def test_api_keys_never_in_defaults(self):
        """R2c: the Screen Assistant's API keys live in the Keychain. No
        Defaults key holds one, only the migration knows upstream's plain-text
        names, and a key never goes into a URL, a print or a log line."""
        defaults_key = re.compile(r"Defaults\[\.\w*ApiKey\]|@Default\(\.\w*ApiKey\)|Key<String\??>\(\"\w*ApiKey\"")
        legacy_name = re.compile(r'"(?:gemini|openai|claude|groq)ApiKey"')
        logging = re.compile(r"\b(?:print|debugPrint|NSLog|os_log)\(|\b(?:log|logger|Logger)\.(?:debug|info|notice|error|warning|fault|critical|trace|log)\(")
        interpolated_key = re.compile(r"\\\(\s*[\w.]*[Aa]pi[Kk]ey")
        in_defaults, named, logged, in_url = [], set(), [], []
        for path in sorted(SOURCES.rglob("*.swift")):
            relative = path.relative_to(SOURCES).as_posix()
            for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                code = line.split("//", 1)[0]
                place = f"{relative}:{number}"
                if defaults_key.search(code):
                    in_defaults.append(place)
                if legacy_name.search(code):
                    named.add(relative)
                if logging.search(code) and interpolated_key.search(code):
                    logged.append(place)
                if re.search(r"URL\(|URLComponents\(|URLQueryItem\(|appendingPathComponent\(", code) and (
                        interpolated_key.search(code) or re.search(r'[?&]key=|URLQueryItem\(name:\s*"key"', code)):
                    in_url.append(place)
        self.assertEqual(in_defaults, [], "API keys in Defaults")
        self.assertEqual(named, {"managers/ScreenAssistantKeyStore.swift"}, "plain-text key names outside the migration")
        self.assertEqual(logged, [], "an API key in a print or a log line")
        self.assertEqual(in_url, [], "an API key in a URL")

        # The key store logs statuses, account names and a count, never a value.
        store = (SOURCES / "managers" / "ScreenAssistantKeyStore.swift").read_text(encoding="utf-8")
        log_lines = [line for line in store.splitlines() if logging.search(line)]
        self.assertTrue(log_lines, "the scan must see the store's log lines")
        for line in log_lines:
            for interpolation in re.findall(r"\\\(([^,)]+)", line):
                self.assertIn(interpolation.strip(), {"account.rawValue", "error.status", "moved"}, line.strip())

        # Gemini takes its key in a header, as the other providers do.
        manager = (SOURCES / "managers" / "ScreenAssistantManager.swift").read_text(encoding="utf-8")
        self.assertIn('"x-goog-api-key": apiKey', manager)
        self.assertNotIn("?key=", manager)

    def test_voice_questions_and_the_microphone_text_are_gone(self):
        """Д6: Skerry has no microphone access (ENABLE_RESOURCE_ACCESS_AUDIO_INPUT
        = NO), so the assistant records nothing and asks for nothing."""
        project = PROJECT.read_text()
        self.assertNotIn("NSMicrophoneUsageDescription", project)
        self.assertEqual(2, project.count("ENABLE_RESOURCE_ACCESS_AUDIO_INPUT = NO;"))
        for path in sorted(SOURCES.rglob("*.swift")):
            text = path.read_text(encoding="utf-8")
            for call in ["AVAudioRecorder", "RecordingButton", "toggleRecording("]:
                self.assertNotIn(call, text, path.relative_to(ROOT).as_posix())


if __name__ == "__main__":
    unittest.main()
