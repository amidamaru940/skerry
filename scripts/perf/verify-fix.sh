#!/bin/zsh
# Skerry — a fork of Atoll (DynamicIsland)
# Copyright (C) 2026 amidamaru940 and Skerry contributors
# Licensed under the GNU General Public License v3.0 or later; see LICENSE.
#
# Checks the overheating fix on this Mac, steps 2–5 of the hand-over:
# the installed version, a build, every test, and the energy measurements
# before (the installed app) and after (the new build). Stops at the first
# stage that fails, with the log to look at. Nothing is installed: the new
# build runs from the build folder, /Applications stays as it is.
#
# Usage: scripts/perf/verify-fix.sh [stage ...]
#   stages: version build test python before after summary   (default: all, in that order)
#   SKERRY_VERIFY   build folder (default build/verify)
#
# The music runs ask for music to be started and wait for Enter; the idle
# runs need the pointer left alone for two minutes. On the charger, please.

set -uo pipefail
cd "$(dirname "$0")/../.."

OUT="${SKERRY_VERIFY:-build/verify}"
RESULTS="docs/perf/results-$(date +%Y%m%d)"
INSTALLED="/Applications/Skerry.app"
mkdir -p "$OUT" "$RESULTS"
STAGES=("$@")
(( ${#STAGES} )) || STAGES=(version build test python before after summary)

fail() { echo "✗ $1" >&2; exit 1; }
quit_skerry() {
  osascript -e 'tell application "Skerry" to quit' >/dev/null 2>&1 || true
  sleep 3
  pkill -x Skerry 2>/dev/null || true
  sleep 1
}
wait_launch() { sleep 20; pgrep -x Skerry >/dev/null || fail "Skerry did not start"; }
ask() { print -n "$1 — then press Enter "; read -r _; }

for stage in "${STAGES[@]}"; do
  case "$stage" in
    version)
      VERSION="$(defaults read "$INSTALLED/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo 'not installed')"
      BUILT="$(stat -f '%Sm' "$INSTALLED/Contents/MacOS/Skerry" 2>/dev/null || echo '?')"
      echo "installed=$VERSION binary-modified=$BUILT" | tee "$RESULTS/installed-version.txt"
      ;;
    build)
      echo "Building Release (ad-hoc)…"
      xcodebuild build -project DynamicIsland.xcodeproj -scheme DynamicIsland -configuration Release \
        -destination "platform=macOS,arch=arm64" -derivedDataPath "$OUT/DerivedData" \
        CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= CODE_SIGN_STYLE=Manual \
        >"$OUT/build.log" 2>&1 || { grep -E "error:" "$OUT/build.log" | sort -u | head -40; fail "build failed: $OUT/build.log"; }
      grep -c "warning:" "$OUT/build.log" | xargs echo "warnings:"
      echo "✓ build"
      ;;
    test)
      echo "Unit tests (safe run: own defaults domain, cleaned afterwards)…"
      # Sockets must stay at zero for the whole run (PROGRESS.md §5).
      ( while sleep 0.5; do lsof -nP -i -a -c Skerry 2>/dev/null; done ) >"$OUT/test-sockets.txt" &
      WATCH=$!
      xcodebuild test -project DynamicIsland.xcodeproj -scheme DynamicIsland -only-testing:DynamicIslandTests \
        -destination "platform=macOS,arch=arm64" -derivedDataPath "$OUT/DerivedData-test" \
        -resultBundlePath "$OUT/tests-$(date +%H%M%S).xcresult" \
        -test-timeouts-enabled YES -maximum-test-execution-time-allowance 300 -allowProvisioningUpdates \
        >"$OUT/test.log" 2>&1
      STATUS=$?
      kill $WATCH 2>/dev/null
      defaults delete io.github.amidamaru940.skerry.dev >/dev/null 2>&1 || true
      rm -f ~/Library/Preferences/Atoll.PinnedLyricsTests.*.plist
      rm -rf ~/Library/Application\ Support/io.github.amidamaru940.skerry.dev
      grep -E "Executed [0-9]+ tests" "$OUT/test.log" | tail -1
      grep -E "error:|failed \(" "$OUT/test.log" | sort -u | head -40
      [[ -s "$OUT/test-sockets.txt" ]] && { echo "sockets seen during the tests:"; sort -u "$OUT/test-sockets.txt" | head; }
      (( STATUS == 0 )) || fail "unit tests failed: $OUT/test.log"
      grep -q "EnergyTests" "$OUT/test.log" || echo "! EnergyTests did not appear in the log"
      echo "✓ unit tests"
      ;;
    python)
      python3 -m unittest discover tests 2>&1 | tail -3
      python3 -m unittest discover tests >/dev/null 2>&1 || fail "Python tests failed"
      echo "✓ Python tests"
      ;;
    before)
      quit_skerry
      scripts/perf/measure.sh baseline || fail "baseline"
      open "$INSTALLED"; wait_launch
      ask "Installed Skerry: leave the island closed, no music, hands off for 2 minutes"
      scripts/perf/measure.sh before-idle || fail "before-idle"
      ask "Start music (the player you use most) and close the island"
      scripts/perf/measure.sh before-music || fail "before-music"
      ask "Stop the music"
      quit_skerry
      ;;
    after)
      APP="$(ls -d "$OUT"/DerivedData/Build/Products/Release/Skerry.app 2>/dev/null)"
      [[ -d "$APP" ]] || fail "no new build: run the build stage first"
      quit_skerry
      open -n "$APP"; wait_launch
      ask "New build: leave the island closed, no music, hands off for 2 minutes"
      scripts/perf/measure.sh after-idle || fail "after-idle"
      ask "Start the same music and close the island"
      scripts/perf/measure.sh after-music || fail "after-music"
      ask "Stop the music. Next 60 s: keep moving the pointer around the screen (the hover ears)"
      scripts/perf/measure.sh after-mouse 60 || fail "after-mouse"
      quit_skerry
      open "$INSTALLED"
      ;;
    summary)
      {
        echo "| run | Skerry cpu% idlew power | WindowServer cpu% idlew power | assertions, listening, non-loopback, children |"
        echo "|---|---|---|---|"
        for dir in docs/perf/{baseline,before-idle,before-music,after-idle,after-music,after-mouse}-*(N/); do
          s="$dir/summary.txt"; [[ -f "$s" ]] || continue
          name="${${dir:t}%-*-*}"
          app="$(grep '^app ' "$s" | sed 's/.*: //')"
          ws="$(grep '^WindowServer ' "$s" | sed 's/.*: //')"
          rest="$(grep '^assertions' "$s")"
          echo "| $name | $app | $ws | $rest |"
        done
      } | tee "$RESULTS/table.md"
      ;;
    *) fail "unknown stage $stage" ;;
  esac
done
echo "Results: $RESULTS"
