# Contributing to Skerry

Thanks for helping! Issues and pull requests are welcome.

- **Bugs and ideas:** open an issue with your macOS version, what you did, what you expected and what happened. Screenshots help, but please leave out anything personal.
- **Pull requests:** keep them focused on one change. Match the style of the code around them, and add or update tests for what you change.

## Building

See [Build from source](README.md#build-from-source). In short: open `DynamicIsland.xcodeproj` and Run. Signing is ad hoc unless you add your own team in `Config/Local.xcconfig`, which git ignores.

## House rules

- **No new dependencies** (Swift packages, binaries) without discussing them in an issue first.
- **Nothing networked on by default.** A new network address needs an entry in `tests/network_allowlist.txt` that names the setting enabling it.
- **Tests stay offline.** They never touch the real settings, clipboard or keychain: use your own `UserDefaults` suites, private pasteboards and temporary folders.
- **New text is translated.** Interface strings go into `DynamicIsland/Localizable.xcstrings` with a Russian translation.
- **Licensing.** Skerry is GPL-3.0 and keeps Atoll's and boring.notch's notices. By contributing you agree to license your work under the same terms.

## Running the tests

```bash
xcodebuild test -project DynamicIsland.xcodeproj -scheme DynamicIsland -destination 'platform=macOS'
python3 -m unittest discover tests
```
