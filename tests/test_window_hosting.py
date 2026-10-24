"""The windows Skerry sizes itself never have a SwiftUI hosting view as
their contentView. There SwiftUI attaches its own window-sizing helper,
whatever the view's sizingOptions, and resizes the window from
windowDidLayout while Skerry sets the frame too: the island re-entered
Update Constraints until AppKit threw (crashes 23.10, 09:53 and 10:20).
They go in through NSWindow.setSelfSizedContent, inside a plain container."""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "DynamicIsland"


def function_body(source, name):
    """The text between the braces of `func name(` or `func name<`."""
    start = source.index("{", re.search(rf"func {name}[(<]", source).start())
    depth = 0
    for index in range(start, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[start:index + 1]
    raise ValueError(name)


class SelfSizedWindowTests(unittest.TestCase):
    def assert_self_sized(self, path, function, host):
        body = function_body((SOURCES / path).read_text(), function)
        self.assertIn(f"setSelfSizedContent({host})", body)
        self.assertNotRegex(body, rf"\.contentView = {host}\b")

    def test_the_island_window(self):
        self.assert_self_sized("DynamicIslandApp.swift", "createDynamicIslandWindow", "host")

    def test_the_picture_preview_panel(self):
        self.assert_self_sized("components/Notch/NotchClipboardView.swift", "show", "hosting")


if __name__ == "__main__":
    unittest.main()
