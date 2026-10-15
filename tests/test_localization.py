# Skerry — a fork of Atoll (DynamicIsland)
# Copyright (C) 2026 amidamaru940 and Skerry contributors
# Licensed under the GNU General Public License v3.0 or later; see LICENSE.

"""The interface exists in English (the source language) and Russian."""

import json
import pathlib
import plistlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
APP = ROOT / "DynamicIsland"
CATALOG = APP / "Localizable.xcstrings"
PROJECT = ROOT / "DynamicIsland.xcodeproj" / "project.pbxproj"
FORK_HEADER = "Skerry — a fork of Atoll"

PLACEHOLDER = re.compile(r"%(?:\d+\$)?(?:ll|l|h)?[@dDuUxXcCsS]|%(?:\d+\$)?\.?\d*f")

# Literal keys of the usual localizing calls; interpolated strings are left to the compiler.
LOCALIZED_LITERAL = re.compile(
    r'(?:String\(localized:\s*|\bText\(|\bButton\(|\bToggle\(|\bPicker\(|\bLabel\(|\.help\(|'
    r'\.navigationTitle\(|\.alert\(|\bLink\(|\bStepper\(|\bSlider\(|LocalizedStringKey\()'
    r'\s*"((?:[^"\\]|\\.)*)"'
)


def load_catalog():
    return json.loads(CATALOG.read_text(encoding="utf-8"))["strings"]


def placeholders(text):
    return sorted(re.sub(r"\d+\$", "", m.group(0)) for m in PLACEHOLDER.finditer(text))


def translatable(entry):
    return entry.get("shouldTranslate", True) and entry.get("extractionState") != "stale"


def fork_sources():
    for path in sorted(APP.rglob("*.swift")):
        text = path.read_text(encoding="utf-8")
        if FORK_HEADER in text[:400]:
            yield path, text


class LocalizationTests(unittest.TestCase):
    def test_russian_is_a_known_region(self):
        regions = re.search(r"knownRegions = \(([^)]*)\);", PROJECT.read_text(encoding="utf-8")).group(1)
        self.assertIn("ru,", regions.split())
        self.assertIn("en,", regions.split())

    def test_every_catalog_string_has_russian(self):
        missing = [key for key, entry in load_catalog().items()
                   if translatable(entry) and "ru" not in entry.get("localizations", {})]
        self.assertEqual(missing, [], "strings without a Russian translation")

    def test_russian_keeps_the_placeholders(self):
        wrong = []
        for key, entry in load_catalog().items():
            unit = entry.get("localizations", {}).get("ru", {}).get("stringUnit")
            if unit and placeholders(key) != placeholders(unit["value"]):
                wrong.append((key, unit["value"]))
        self.assertEqual(wrong, [])

    def test_plural_strings_have_every_form(self):
        for key, entry in load_catalog().items():
            ru = entry.get("localizations", {}).get("ru", {})
            plural = ru.get("variations", {}).get("plural")
            if not plural:
                continue
            self.assertTrue({"one", "few", "many", "other"} <= set(plural), key)
            english = entry["localizations"].get("en", {}).get("variations", {}).get("plural", {})
            self.assertTrue({"one", "other"} <= set(english), f"{key}: English plural forms")

    def test_fork_strings_are_in_the_catalog(self):
        catalog = load_catalog()
        missing = []
        for path, text in fork_sources():
            code = "\n".join(line for line in text.splitlines() if not line.lstrip().startswith("//"))
            for match in LOCALIZED_LITERAL.finditer(code):
                literal = match.group(1)
                if not literal or "\\(" in literal:
                    continue
                key = literal.replace('\\"', '"').replace("\\n", "\n").replace("\\\\", "\\")
                if key not in catalog:
                    missing.append((path.relative_to(ROOT).as_posix(), key))
        self.assertEqual(missing, [], "add these to Localizable.xcstrings with Russian")
        self.assertGreater(sum(1 for _ in fork_sources()), 20)

    def test_permission_requests_are_in_russian(self):
        strings = (APP / "ru.lproj" / "InfoPlist.strings").read_text(encoding="utf-8")
        translated = set(re.findall(r'^"([A-Za-z]+)" = "[^"]+";$', strings, re.MULTILINE))
        project_keys = set(re.findall(r"INFOPLIST_KEY_(NS\w+UsageDescription) =", PROJECT.read_text(encoding="utf-8")))
        with (APP / "Info.plist").open("rb") as handle:
            plist_keys = {key for key in plistlib.load(handle) if key.endswith("UsageDescription")}
        self.assertTrue(project_keys | plist_keys)
        self.assertEqual((project_keys | plist_keys) - translated, set())
        self.assertIn("CFBundleDisplayName", translated)

    def test_wrong_upstream_translations_are_fixed(self):
        catalog = load_catalog()

        def russian(key):
            return catalog[key]["localizations"]["ru"]["stringUnit"]["value"]

        self.assertIn("расширения", russian(
            "Enable extensions to allow third-party apps to display live activities and lock screen widgets in Skerry."))
        self.assertEqual(russian("Done"), "Готово")
        self.assertEqual(russian("All"), "Все")  # was «Выравнивание» (found in phase 5)
        self.assertEqual(russian("Usage"), "Расход")
        self.assertEqual(russian('Are you sure you want to delete "%@"?'), "Удалить «%@»?")
        # Found in the live check, 15.10: a setting under a word from elsewhere.
        self.assertEqual(russian("Media change with horizontal gestures"), "Переключение треков свайпом")
        self.assertIn("macOS 26", russian("Liquid Glass requires macOS 26 or later."))

    def test_sentences_are_not_translated_by_a_word(self):
        # Upstream filled some sentences with a stray word or a heading
        # («Файл», «Стиль дисплея», «Жидкое стекло»): a sentence of six
        # words or more never comes out under a third of its length.
        short = []
        for key, entry in load_catalog().items():
            if not translatable(entry):
                continue
            value = entry.get("localizations", {}).get("ru", {}).get("stringUnit", {}).get("value")
            if value and len(key.split()) >= 6 and len(value) < len(key) / 3:
                short.append((key, value))
        self.assertEqual(short, [])


if __name__ == "__main__":
    unittest.main()
