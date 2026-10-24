# Changelog

All notable changes to Skerry are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). For the history
before the fork, see [Atoll's changelog](https://github.com/Ebullioscopic/Atoll/blob/dev/CHANGELOG.md).

## [1.1.7] — 2026-10-23

### Added
- **A trash in "Buffer".** A small trash beside pause clears what the filter shows: on "All" the copies and the screenshots, on "Shots" the screenshots, on "Text", "Links" and "Files" those copies. Pinned copies stay, and "Cleared · N — Undo" puts everything back for 5 seconds. Clipboard screenshots are then deleted; saved screenshots only leave "Buffer", their files are not touched. "Clear" in the "…" menu does the same.

### Fixed
- **"Clear History" seemed to do nothing** when "Buffer" held only screenshots: it cleared the copies alone.

## [1.1.6] — 2026-10-23

### Fixed
- **Videos on any site, not only YouTube.** A video that reports no artist (an episode on a series site, a film) was treated like an Instagram Reel: hidden, with the music kept on screen and the controls on hold. Only short clips (under 5 minutes) are held now; longer videos show on the island and its buttons control them.
- **"Resume" no longer looks live when it can't work.** While a video in the browser holds the system's controls, the paused-track strip on "Now" dims "Resume" and says "Controls are with a video in …", as the player already did; before, the button silently did nothing.

## [1.1.5] — 2026-10-23

### Fixed
- **A crash while screenshots came into the open "Buffer".** SwiftUI resized the island's window on its own while Skerry set its size too, and the two re-entered AppKit's layout until it threw. 1.1.2 had removed only part of this. The island and the picture preview are now sized by Skerry alone.
- **The picture preview was empty since 1.1.2.** Resting the pointer on a picture in "Buffer" opened a preview with no size; it shows the picture again.

## [1.1.4] — 2026-10-23

### Fixed
- **"Paste into Claude · N" closed the island and pasted nothing.** The closed island kept the keyboard, so the paste stopped before its first ⌘V (it never pastes into the island). The island now hands the keyboard back to the app in front as it closes.
- **The "where to" list held a macOS prompt.** The window asking for Accessibility after a reinstall came forward and became a paste target; its ⌘V only beeped. Only apps with a Dock icon are remembered now.
- **"Buffer" cut off on the first open, whole on the second.** With copies in the history, the island measured only the copies and not the film above them, so it grew too little and stayed cut until reopened. It now grows to the film and the copies at once.

## [1.1.3] — 2026-10-23

### Fixed
- **"Buffer" cut off with the paste key missing.** After the island had shrunk to "No copies yet", a new screenshot batch appeared above it but the island did not grow back, so the film was cut and "Paste into … · N" sat below the edge. The Buffer now grows when its content runs past the island.

## [1.1.2] — 2026-10-23

### Fixed
- A rare crash while the island or a picture preview resized itself (AppKit's layout loop in a SwiftUI window); the island and the preview panel are now sized only by Skerry.

## [1.1.1]

### Fixed
- **Pasting a batch into Claude, Chrome or Telegram.** "Paste into … · 3" did not always paste every shot there. Each shot now goes in as a picture, one after another, so all three arrive. If another app comes forward or the island opens mid-way, pasting stops and the rest are copied for your own ⌘V; copying something else stops it too.
- **Clipboard screenshots from the first launch.** Screenshots taken to the clipboard (⌃⇧⌘4) were collected only after the screenshot folder had been asked for, so with "Skip" on the first launch they were lost. They are now collected from launch, need no folder, and expire within a day even if the folder was never asked for.
- **"Do Not Disturb" no longer hides under the camera.** The closed island gives the moon and the Focus name equal wings, so the name starts after the camera; a long name fades at 150 pt. Battery, AirPods, timer, reminder, recording and extension indicators got equal wings too.

### Changed
- **Clipboard screenshots are now collected by default**, also after updating from 1.1.0. Screenshots taken to the clipboard (⌃⇧⌘4) are kept only as files in a local temporary folder, so they can be pasted or dragged as a batch, and are deleted within a day. Turn this off in Settings → Screenshots → "Also collect clipboard screenshots".
- **Pictures you can tell apart.** A picture in "All" shows a larger thumbnail with its size, and the pointer resting on it opens a preview beside the island that never takes the keyboard. VoiceOver reads where the picture came from and when.
- Without access to the screenshot folder, "Screenshots" still shows the clipboard screenshots.
- Turning on only the clipboard screenshots no longer asks for the Desktop folder.
- "Nothing to paste: the shots are gone" when a batch's files are gone.

## [1.1.0]

### Changed
- **A new look for the island** (concept E, "edge of light"): the closed island, "Now" and "Buffer" are a black body without grey plates; colour comes only as light from what is shown.
- **"Buffer" v3:** filters as words, a film of screenshots with one "Paste into … · N" key, the history in two columns, deleting with "Undo". Every function of the previous tab is kept.
- **The menu bar stays free.** The open island leaves the other apps' menus uncovered: only a neck over the camera, the panel below. It opens on hover at once.
- **A full-screen film leaves the island empty.**

### Security
- Recovery after a crash, no permission prompts at launch, and the Screen Assistant's API keys in the Keychain.

### Fixed
- The Russian interface was checked in full (454 corrections).

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
