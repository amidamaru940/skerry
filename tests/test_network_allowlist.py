import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "DynamicIsland"
ALLOWLIST = ROOT / "tests" / "network_allowlist.txt"

# Text files that can carry a URL literal. String catalogs (*.xcstrings) are
# translations, not code, and are skipped.
SCANNED_SUFFIXES = {
    ".swift", ".m", ".mm", ".h", ".hpp", ".c", ".cpp",
    ".plist", ".json", ".strings", ".entitlements", ".js", ".html", ".svg",
}
# Stops at quotes, whitespace, string interpolation ("\(") and closing brackets.
URL_PATTERN = re.compile(r"""https?://[^\s"'<>`\\)\]]*""")


def source_urls():
    """Every http(s) literal in the app sources, mapped to where it occurs."""
    found = {}
    for path in sorted(SOURCES.rglob("*")):
        if not path.is_file() or path.suffix not in SCANNED_SUFFIXES:
            continue
        for number, line in enumerate(path.read_text(errors="ignore").splitlines(), 1):
            for match in URL_PATTERN.finditer(line):
                url = match.group(0).rstrip(".,;:")
                found.setdefault(url, []).append(f"{path.relative_to(ROOT)}:{number}")
    return found


def allowlist_entries():
    entries = {}
    for number, raw in enumerate(ALLOWLIST.read_text().splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = [part.strip() for part in line.split(" | ")]
        entries[parts[0]] = (number, parts)
    return entries


class NetworkAllowlistTests(unittest.TestCase):
    def test_every_source_url_is_allowlisted(self):
        allowed = allowlist_entries()
        missing = {url: places for url, places in source_urls().items() if url not in allowed}

        self.assertEqual(
            {}, missing,
            "New network address(es) in the sources. Add each to tests/network_allowlist.txt "
            "with the feature that uses it and the setting that enables it.",
        )

    def test_allowlist_has_no_stale_entries(self):
        found = source_urls()
        stale = [url for url in allowlist_entries() if url not in found]

        self.assertEqual([], stale, "Allowlist entries no longer found in the sources; remove them.")

    def test_every_entry_names_a_feature_and_how_it_is_enabled(self):
        for url, (number, parts) in allowlist_entries().items():
            with self.subTest(url=url):
                self.assertEqual(3, len(parts), f"line {number}: expected 'URL | feature | how enabled'")
                self.assertTrue(parts[1] and parts[2], f"line {number}: empty feature or enabling note")

    def test_scanner_finds_known_addresses(self):
        # Guards against a scanner change that silently matches nothing.
        found = source_urls()

        self.assertIn("https://lrclib.net/api/search?track_name=", found)
        self.assertIn("https://wttr.in/", found)
        self.assertGreater(len(found), 40)


if __name__ == "__main__":
    unittest.main()
