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
    r"setupBluetoothObservers\(\)$",
    r"open\(path, O_EVTONLY\)",
    r"contentsOfDirectory\(at: downloadsDirectory",
    r"Self\.sample\(in: downloadsDirectory",
]
GUARD = "AppRuntimeEnvironment.mayAskForPermissions"
WINDOW = 20  # lines above the call that may hold the guard (the top of its function)


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

    def test_the_test_host_is_never_allowed_to_ask(self):
        source = (SOURCES / "helpers" / "AppRuntimeEnvironment.swift").read_text()
        self.assertIn("mayAskForPermissions: Bool = !isUITesting && !isHostingUnitTests", source)


if __name__ == "__main__":
    unittest.main()
