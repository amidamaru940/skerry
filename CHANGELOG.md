# Changelog

All notable changes to Skerry are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). For the history
before the fork, see [Atoll's changelog](https://github.com/Ebullioscopic/Atoll/blob/dev/CHANGELOG.md).

## [1.0.3]

### Changed
- **Sliders are easy to catch.** Seeking and the volume needed a click right on a thin line. The volume now takes clicks within 24 points (it was 6), the player's seek bar within 20 (14) and the compact one within 18 (11), and each thickens as soon as the pointer is over it, not only while dragged. The player is no taller than before.

## [1.0.2]

### Fixed
- **Reminders in "Next".** Reminders are a macOS permission of their own, and Skerry never asked for it, so they were missing from "Next" with nothing to say why. While that permission is unanswered, "Next" now offers "Reminders too · Allow Access", and a click asks macOS. Reminders whose due date comes without a calendar are no longer dropped.
- **Fewer permission prompts.** Skerry asks for the Downloads folder only when the download listener is on, not on every launch.

### Changed
- **Running the tests leaves your Mac alone.** The unit-test host is a second Skerry to macOS. It no longer asks for any permission, never shows its island, and never takes the keyboard. A source scan keeps new prompting calls behind the guard.
- The README shows a screenshot batch and the shelf.

## [1.0.1]

### Fixed
- **Seeking in the compact player.** The progress line under the title was only drawn, so music could not be wound in the one-row player. A click or a drag now seeks, and the time shows while you drag.
- **Videos no longer take the player over.** A browser hands macOS one tab at a time, so a video without track details, such as Instagram Reels, replaced the music playing in another tab, and the controls reached the video. The music now stays on screen. Its controls rest, with "Controls are with a video in Chrome", until the browser hands them back when the video is closed.
- **Idle animations after moving the app.** The built-in animations were stored with the app's path and disappeared once the app was moved or renamed.
- **Track changes without a gap.** A browser reports a track change in steps: about a second of nothing, then the title, then the rest, then the artwork. The player disappeared and redrew itself for each. The previous track now stays until the next one has arrived, and that one appears complete.
- **Tracks no longer switch by themselves.** The swipe that changes tracks added up scrolling that was never a swipe: sideways drift while scrolling a page near the top of the screen, gestures that ended off the island, and mouse-wheel nudges minutes apart.

### Changed
- **The Clipboard tab is as tall as what it shows.** An empty clipboard is a thin strip with one line instead of a large square, and the island grows with the copies up to the full grid.

### Added
- Issue and pull request templates, and a security policy.

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
