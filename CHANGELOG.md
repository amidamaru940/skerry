# Changelog

All notable changes to Skerry are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). For the history
before the fork, see [Atoll's changelog](https://github.com/Ebullioscopic/Atoll/blob/dev/CHANGELOG.md).

## [1.0.0]

First release of Skerry, forked from Atoll at `868c25d`.

### Added
- **Screenshot batches.** New screenshots gather into batches at the notch, and "Paste into … · N" pastes a whole batch, or the shots picked from it, into the app you were working in. You can drag a batch by its title, select all, open Quick Look, use AirDrop, show it in Finder, and mark up several shots one after another. Optionally, screenshots taken to the clipboard join the batch from a temporary folder that clears itself within a day.
- **Clipboard tab.**
  - Cards with source app and time, and filters (All, Screenshots, Text, Links, Files).
  - Search that understands Russian, a folded "Pinned" row, and ⌘1–⌘9 to paste.
  - Pause recording, with an indicator on the closed island.
- **Now tab.**
  - A calm player: the extras appear on hover, a volume popover, "Nothing playing" with Resume.
  - "Next" with your upcoming events, the Auto music source with a priority order, and track changes by swiping the closed island.
- **Compact layout:** fewer tabs, the player in one row with volume and the next two events.
- **Closed island:** hover "ears" beside the notch, wings centred on the camera, a priority order for live indicators, flashes for a new screenshot, a picked colour and shelf drops, and Keep Awake with its time left.
- **Presenting mode:** while the screen is shared or recorded, clipboard and screenshots show only their titles and notifications stay quiet.
- **Design system and a new header:** tabs with an "unseen" dot, a status capsule, and one "…" menu.
- **Settings and languages:** settings in eight sections, each setting on one page, with "Configure ›" links where pages meet. Onboarding in three steps. Full Russian translation with an in-app language switch.
- **Tooling:** `scripts/make-release.sh` builds an ad-hoc signed DMG. Signing comes from `Config/Signing.xcconfig`, with an optional local team.

### Changed
- **Privacy by default.**
  - Every networked feature is off until you turn it on, and nothing listens on a port.
  - Clipboard history stays in memory, and passwords are never recorded.
  - A test lists every network address in the code.
- **Updates and permissions:** Sparkle updates are switched off, and the camera entitlement is removed.
- **Data:** app data lives in `~/Library/Application Support/<bundle id>`, not in iCloud Documents.

### Removed
- The minimalistic mode (replaced by Compact), the separate Screenshots tab (merged into Clipboard), the timer popover and the old onboarding.
- About forty files of code nothing used any more.
