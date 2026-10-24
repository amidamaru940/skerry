#!/bin/zsh
# Skerry — a fork of Atoll (DynamicIsland)
# Copyright (C) 2026 amidamaru940 and Skerry contributors
# Licensed under the GNU General Public License v3.0 or later; see LICENSE.
#
# One step of `git bisect run` for the overheating regression: build the
# checked-out commit, run it with the island closed and no music for 60 s,
# and answer good or bad from its CPU and WindowServer's.
#
#   git bisect start <bad> <good>
#   git bisect run scripts/perf/bisect-step.sh
#
# Copy this script out of the tree first (older commits do not have it):
#   cp scripts/perf/bisect-step.sh ~/bisect-step.sh && git bisect run ~/bisect-step.sh
#
# Settings, in the environment:
#   BISECT_DERIVED     build folder (default build/bisect in the checkout)
#   BISECT_SECONDS     measurement length (default 60)
#   BISECT_APP_CPU     app CPU % above which the commit is bad (default 1.0)
#   BISECT_WS_DELTA    WindowServer CPU % above the baseline that is bad (default 3)
#   BISECT_BASELINE    WindowServer CPU % with no Skerry running; measured once
#                      and kept in $BISECT_DERIVED/ws-baseline when not given
#
# Exit codes are git bisect's: 0 good, 1 bad, 125 skip (does not build).
# Every commit runs with the settings of the installed app, as the user has
# them: the bundle identifier changed in 2d618b2, and that build copies the
# old settings over once.

set -uo pipefail
DERIVED="${BISECT_DERIVED:-$(git rev-parse --show-toplevel)/build/bisect}"
SECONDS_RUN="${BISECT_SECONDS:-60}"
APP_LIMIT="${BISECT_APP_CPU:-1.0}"
WS_DELTA="${BISECT_WS_DELTA:-3}"
COMMIT="$(git rev-parse --short HEAD)"
LOG="$DERIVED/bisect.log"
mkdir -p "$DERIVED"

quit_all() {
  for name in Skerry; do
    osascript -e "tell application \"$name\" to quit" >/dev/null 2>&1 || true
  done
  sleep 2
  pkill -x Skerry 2>/dev/null
  sleep 1
}

# WindowServer CPU, averaged over $1 seconds (first top sample dropped).
windowserver_cpu() {
  top -l $(( $1 / 3 + 1 )) -s 3 -stats pid,command,cpu | awk '
    /WindowServer/ { n++; if (n == 1) next; s += $3; c++ }
    END { printf "%.2f\n", (c ? s / c : 0) }'
}

quit_all
if [[ -z "${BISECT_BASELINE:-}" ]]; then
  if [[ -s "$DERIVED/ws-baseline" ]]; then
    BISECT_BASELINE="$(cat "$DERIVED/ws-baseline")"
  else
    echo "Measuring the WindowServer baseline (no Skerry) for $SECONDS_RUN s…"
    BISECT_BASELINE="$(windowserver_cpu "$SECONDS_RUN")"
    echo "$BISECT_BASELINE" > "$DERIVED/ws-baseline"
  fi
fi

echo "[$COMMIT] building…"
if ! xcodebuild build -project DynamicIsland.xcodeproj -scheme DynamicIsland -configuration Release \
    -destination "platform=macOS,arch=arm64" -derivedDataPath "$DERIVED/DerivedData" \
    CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= CODE_SIGN_STYLE=Manual \
    CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES >"$DERIVED/build-$COMMIT.log" 2>&1; then
  echo "[$COMMIT] does not build: skip" | tee -a "$LOG"
  exit 125
fi
APP="$(ls -dt "$DERIVED"/DerivedData/Build/Products/Release/*.app 2>/dev/null | head -1)"
[[ -d "$APP" ]] || { echo "[$COMMIT] no app: skip" | tee -a "$LOG"; exit 125; }

echo "[$COMMIT] running $(basename "$APP") for $SECONDS_RUN s (do not touch the island)…"
open -g -n "$APP"
sleep 15   # launch, first layout, Now Playing adapter
PID="$(pgrep -nx Skerry)"
[[ -n "$PID" ]] || { echo "[$COMMIT] did not start: skip" | tee -a "$LOG"; quit_all; exit 125; }

RESULT="$(top -l $(( SECONDS_RUN / 3 + 1 )) -s 3 -stats pid,command,cpu | awk -v pid="$PID" '
  $1 == pid { a++; if (a > 1) { app += $(NF); ac++ } }
  /WindowServer/ { w++; if (w > 1) { ws += $(NF); wc++ } }
  END { printf "%.2f %.2f\n", (ac ? app / ac : 0), (wc ? ws / wc : 0) }')"
quit_all

APP_CPU="${RESULT%% *}"
WS_CPU="${RESULT##* }"
VERDICT="$(awk -v a="$APP_CPU" -v w="$WS_CPU" -v b="$BISECT_BASELINE" -v al="$APP_LIMIT" -v wd="$WS_DELTA" \
  'BEGIN { print ((a > al || w - b > wd) ? "bad" : "good") }')"
echo "[$COMMIT] app ${APP_CPU}% WindowServer ${WS_CPU}% (baseline ${BISECT_BASELINE}%): $VERDICT" | tee -a "$LOG"
[[ "$VERDICT" == good ]]
