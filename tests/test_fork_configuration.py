import plistlib
import re
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "DynamicIsland.xcodeproj" / "project.pbxproj"
INFO_PLIST = ROOT / "DynamicIsland" / "Info.plist"
ENTITLEMENTS = ROOT / "DynamicIsland" / "DynamicIsland.entitlements"
NOTICE = ROOT / "NOTICE"

ATOLL_TEAM = "9Y64TRM77N"
BASE_COMMIT = "868c25d4a1128eda9c556eb08f09468d9766219f"


def app_target_configs(project):
    """Build settings blocks of the app target (the ones that set CODE_SIGN_ENTITLEMENTS)."""
    blocks = re.findall(r"buildSettings = \{(.*?)\n\t\t\t\};", project, re.S)
    return [b for b in blocks if "CODE_SIGN_ENTITLEMENTS = DynamicIsland/DynamicIsland.entitlements;" in b]


class ForkConfigurationTests(unittest.TestCase):
    def test_bundle_identifiers(self):
        project = PROJECT.read_text()

        self.assertEqual(1, project.count("PRODUCT_BUNDLE_IDENTIFIER = io.github.amidamaru940.skerry;"))
        self.assertEqual(1, project.count("PRODUCT_BUNDLE_IDENTIFIER = io.github.amidamaru940.skerry.dev;"))
        self.assertEqual(2, project.count("PRODUCT_BUNDLE_IDENTIFIER = io.github.amidamaru940.skerry.tests;"))
        self.assertEqual(2, project.count("PRODUCT_BUNDLE_IDENTIFIER = io.github.amidamaru940.skerry.uitests;"))
        self.assertNotIn("com.Ebullioscopic.Atoll", project)

    def test_product_and_display_name(self):
        project = PROJECT.read_text()

        self.assertEqual(2, project.count('PRODUCT_NAME = "Skerry";'))
        self.assertEqual(2, project.count('INFOPLIST_KEY_CFBundleDisplayName = "Skerry";'))
        # The Swift module keeps its upstream name so `@testable import Atoll` and upstream merges keep working.
        self.assertEqual(2, project.count("PRODUCT_MODULE_NAME = Atoll;"))

    def test_signing_comes_from_the_xcconfig(self):
        """No team in the project: ad-hoc for anyone, an own team only in the untracked Local.xcconfig."""
        project = PROJECT.read_text()
        configs = app_target_configs(project)
        signing = (ROOT / "Config" / "Signing.xcconfig").read_text()

        self.assertEqual(2, len(configs))  # Debug and Release
        self.assertEqual(2, project.count("baseConfigurationReference = 5CE2A1F0B7C94E3DA0F11A01 /* Signing.xcconfig */;"))
        for config in configs:
            self.assertIn("CODE_SIGN_STYLE = Automatic;", config)
            self.assertIn("ENABLE_HARDENED_RUNTIME = YES;", config)
        self.assertIsNone(re.search(r"^\s*DEVELOPMENT_TEAM = ", project, re.M), "the team belongs in Config/Local.xcconfig")
        self.assertIsNone(re.search(r'^\s*"?CODE_SIGN_IDENTITY(\[[^\]]*\])?"? = ', project, re.M), "the identity too")
        self.assertNotIn(ATOLL_TEAM, project)
        self.assertIn("CODE_SIGN_IDENTITY = -", signing)
        self.assertIn('#include? "Local.xcconfig"', signing)
        ignored = subprocess.run(["git", "check-ignore", "-q", "Config/Local.xcconfig"], cwd=ROOT)
        self.assertEqual(0, ignored.returncode, "Config/Local.xcconfig must never be committed")

    def test_release_is_not_debuggable(self):
        """Apple Development signing injects get-task-allow; Release must not carry it."""
        project = PROJECT.read_text()
        release = [c for c in app_target_configs(project) if "PRODUCT_BUNDLE_IDENTIFIER = io.github.amidamaru940.skerry;" in c]

        self.assertEqual(1, len(release))
        self.assertIn("CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO;", release[0])
        # Coverage counters name every source file (with its full path) and slow the app down.
        self.assertIn("ENABLE_CODE_COVERAGE = NO;", release[0])
        self.assertIn("CLANG_COVERAGE_MAPPING = NO;", release[0])
        self.assertNotIn("Developer ID Application", project)

    def test_info_plist_has_no_sparkle_feed(self):
        info = plistlib.loads(INFO_PLIST.read_bytes())

        for key in ("SUFeedURL", "SUPublicEDKey", "SUEnableDownloaderService", "SUEnableInstallerLauncherService"):
            self.assertNotIn(key, info)
        self.assertIs(info.get("SUEnableAutomaticChecks"), False)

    def test_usage_descriptions_do_not_say_atoll(self):
        project = PROJECT.read_text()
        info = plistlib.loads(INFO_PLIST.read_bytes())

        for line in re.findall(r"INFOPLIST_KEY_NS\w+UsageDescription = .*", project):
            self.assertNotIn("Atoll", line)
        for key, value in info.items():
            if key.endswith("UsageDescription"):
                self.assertNotIn("Atoll", value, key)

    def test_camera_entitlement_removed(self):
        entitlements = plistlib.loads(ENTITLEMENTS.read_bytes())

        self.assertNotIn("com.apple.security.device.camera", entitlements)
        # Hardened Runtime "Resource Access: Camera" would add the entitlement back at signing time.
        project = PROJECT.read_text()
        self.assertEqual(2, project.count("ENABLE_RESOURCE_ACCESS_CAMERA = NO;"))
        self.assertNotIn("ENABLE_RESOURCE_ACCESS_CAMERA = YES;", project)

    def test_notice_records_the_fork(self):
        notice = NOTICE.read_text()

        self.assertIn("Atoll (DynamicIsland) - NOTICE", notice)
        self.assertIn("Skerry is a fork of Atoll (Ebullioscopic/Atoll", notice)
        self.assertIn(BASE_COMMIT, notice)
        self.assertIn("modified in 2026", notice)
        self.assertIn("GNU\nGeneral Public License v3.0", notice)
        self.assertIn("not\naffiliated with", notice)

    def test_test_files_are_not_git_ignored(self):
        """The upstream .gitignore ignores *.py and *.txt; every file in tests/ must be exempt."""
        files = [str(path.relative_to(ROOT)) for path in sorted((ROOT / "tests").iterdir())
                 if path.is_file() and not path.name.startswith(".")]
        # The project's own scripts and config too (the upstream rules ignore *.sh as well).
        files += ["scripts/make-release.sh", "scripts/make_skerry_icon.swift", "Config/Signing.xcconfig",
                  "DynamicIsland.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"]
        result = subprocess.run(["git", "check-ignore", *files], cwd=ROOT, capture_output=True, text=True)

        self.assertEqual("", result.stdout.strip(), "ignored by git; add a !rule to .gitignore")


    def test_each_setting_lives_on_one_page(self):
        # The audit found the same switch on two to four pages (lock screen
        # widgets on Media, Timer and Calendar too; the display style on
        # General and Appearance). Each now has one place, and the other pages
        # point there. The HUD has one copy per HUD style, and only the chosen
        # style's settings are on screen.
        settings = ROOT / "DynamicIsland" / "components" / "Settings"
        one_per_hud_style = {"useColorCodedVolumeDisplay", "useSmoothColorGradient"}
        counts = {}
        for path in sorted(settings.glob("*.swift")):
            for key in re.findall(r"Defaults\.Toggle\(key: \.(\w+)\)", path.read_text(encoding="utf-8")):
                counts[key] = counts.get(key, 0) + 1
        repeated = sorted(key for key, count in counts.items() if count > 1 and key not in one_per_hud_style)
        self.assertEqual(repeated, [])

        view = (settings / "SettingsView.swift").read_text(encoding="utf-8")
        self.assertEqual(view.count("selection: $externalDisplayStyle"), 1, "one display style picker")
        self.assertNotIn("Lock Screen Integration", view, "the copied lock screen sections are gone")

        # Different settings under one title («Temperature unit» for the
        # weather and the CPU, «Cursor» for an AI editor and a colour).
        titles = {}
        for path in sorted(settings.glob("*.swift")):
            source = path.read_text(encoding="utf-8")
            found = re.findall(r'(?:Toggle|Picker|SettingsSegmentedPicker|ColorPicker)\(\s*"([^"]+)"', source)
            found += re.findall(r'Defaults\.Toggle\(key: \.\w+\) \{\s*Text\("([^"]+)"\)', source)
            for title in found:
                titles[title] = titles.get(title, 0) + 1
        hud_styles = {"Volume HUD", "Brightness HUD", "Keyboard Backlight HUD", "Show Percentage", "Use Accent Color",
                      "Material", "Glass mode", "Color-coded Volume", "Smooth color transitions"}
        shared = sorted(title for title, count in titles.items() if count > 1 and title not in hud_styles)
        self.assertEqual(shared, [])

    def test_release_script_builds_ad_hoc_and_offline_friendly(self):
        # No paid Apple account: the public DMG is ad-hoc signed whatever
        # team this Mac uses, and nothing in the script talks to Apple.
        script = (ROOT / "scripts" / "make-release.sh").read_text()
        self.assertIn("CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=", script)
        self.assertIn('"Signature=adhoc"', script)
        self.assertIn("hdiutil create", script)
        for tool in ("notarytool", "altool", "curl ", "wget "):
            self.assertNotIn(tool, script)
        self.assertIn('shasum -a 256 "${DMG:t}"', script, "the published checksum names the file, not a local path")
        self.assertIn('-file-prefix-map \\"$HOME=~\\"', script, "source paths in the binary must not name the builder's home")
        self.assertIn('-file-prefix-map \\"$ROOT_ABS=.\\"', script, "quoted, or xcodebuild splits a path with a space")
        self.assertIn('grep -rlaF "$HOME/" "$APP"', script)
        self.assertIn("STRIP_STYLE=debugging", script, "the debug map names the build folder")
        self.assertIn("ENABLE_CODE_COVERAGE=NO", script)

    def test_the_version_is_the_same_everywhere(self):
        # make-release.sh names the DMG after VERSION; the app reports the
        # project's MARKETING_VERSION; the changelog's top entry is the release.
        version = (ROOT / "VERSION").read_text().strip()
        self.assertRegex(version, r"^\d+\.\d+\.\d+$")
        project = (ROOT / "DynamicIsland.xcodeproj" / "project.pbxproj").read_text()
        self.assertEqual(set(re.findall(r"MARKETING_VERSION = ([^;]+);", project)), {version})
        changelog = (ROOT / "CHANGELOG.md").read_text()
        self.assertEqual(re.search(r"^## \[([^\]]+)\]", changelog, re.M).group(1), version)


    def test_sources_do_not_compile_their_paths_into_the_app(self):
        # In Swift 5 mode #file is the full source path, and every use puts
        # the builder's home folder into the released binary; #fileID does not.
        offenders = []
        for path in sorted((ROOT / "DynamicIsland").rglob("*.swift")):
            for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                code = line.split("//", 1)[0]
                if re.search(r"#file(?!ID)\b|#filePath", code):
                    offenders.append(f"{path.relative_to(ROOT)}:{number}")
        self.assertEqual(offenders, [])


if __name__ == "__main__":
    unittest.main()
