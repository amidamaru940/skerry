#!/bin/zsh
# Skerry — a fork of Atoll (DynamicIsland)
# Copyright (C) 2026 amidamaru940 and Skerry contributors
# Licensed under the GNU General Public License v3.0 or later; see LICENSE.
#
# One short energy measurement of the running Skerry (and WindowServer), the
# way docs/perf/REPORT-energy.md asks for it. Never longer than three minutes,
# writes a few kilobytes, and starts nothing heavy: run it with the Mac on the
# charger.
#
# Usage: scripts/perf/measure.sh <label> [seconds]
#   label    idle | music | baseline | anything; names the output folder
#   seconds  how long top samples (default 120, at most 180)
#
# "baseline" expects Skerry to be quit: it measures WindowServer alone.
# Results: docs/perf/<label>-<date>/ (top.txt, sample.txt, assertions.txt,
# lsof.txt, children.txt, summary.txt). The summary line is what the report's
# before/after table takes.

set -uo pipefail
cd "$(dirname "$0")/../.."

LABEL="${1:?usage: measure.sh <label> [seconds]}"
SECONDS_TOTAL="${2:-120}"
(( SECONDS_TOTAL > 180 )) && SECONDS_TOTAL=180
INTERVAL=3
SAMPLES=$(( SECONDS_TOTAL / INTERVAL ))
(( SAMPLES < 2 )) && SAMPLES=2

OUT="docs/perf/$LABEL-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"

PID="$(pgrep -x Skerry || true)"
PID="${PID%%$'\n'*}"
if [[ "$LABEL" == baseline ]]; then
  [[ -z "$PID" ]] || { echo "Quit Skerry first: the baseline is WindowServer without it." >&2; exit 1; }
else
  [[ -n "$PID" ]] || { echo "Skerry is not running." >&2; exit 1; }
fi

echo "Measuring '$LABEL' for $SECONDS_TOTAL s (pid ${PID:-none})…"
# top's first sample has no CPU history, so it is dropped in the summary.
top -l $(( SAMPLES + 1 )) -s $INTERVAL -stats pid,command,cpu,idlew,power \
  | grep -iE "skerry|amg island|WindowServer" > "$OUT/top.txt" &
TOP=$!

if [[ -n "$PID" ]]; then
  # 10 s of stacks, while top is running (sample costs little).
  sample "$PID" 10 -file "$OUT/sample.txt" >/dev/null 2>&1
  pmset -g assertions | grep -iE "skerry|amg" > "$OUT/assertions.txt" || true
  lsof -nP -i -a -p "$PID" > "$OUT/lsof.txt" 2>/dev/null || true
  # The Now Playing adapter (perl) and any log stream started by the app.
  pgrep -lfP "$PID" > "$OUT/children.txt" || true
fi
wait $TOP

summarise() {
  # $1: regex for the command column. Prints "avg_cpu avg_idlew avg_power samples".
  awk -v pat="$1" '
    tolower($0) ~ pat {
      n[$1]++
      if (n[$1] == 1) next          # first top sample of each pid: no history
      cpu += $(NF-2); idlew += $(NF-1); power += $NF; count++
    }
    END {
      if (count == 0) { print "n/a n/a n/a 0"; exit }
      printf "%.2f %.1f %.2f %d\n", cpu / count, idlew / count, power / count, count
    }' "$OUT/top.txt"
}

APP="$(summarise 'skerry|amg island')"
WS="$(summarise 'windowserver')"
LISTEN="$( [[ -s "$OUT/lsof.txt" ]] && grep -c LISTEN "$OUT/lsof.txt" || echo 0 )"
NONLOOP="$( [[ -s "$OUT/lsof.txt" ]] && grep -E "TCP|UDP" "$OUT/lsof.txt" | grep -vcE "127\.0\.0\.1|\[::1\]|localhost" || echo 0 )"
ASSERT="$( [[ -s "$OUT/assertions.txt" ]] && wc -l < "$OUT/assertions.txt" | tr -d ' ' || echo 0 )"
CHILDREN="$( [[ -s "$OUT/children.txt" ]] && wc -l < "$OUT/children.txt" | tr -d ' ' || echo 0 )"

{
  echo "label=$LABEL seconds=$SECONDS_TOTAL pid=${PID:-none} date=$(date '+%Y-%m-%d %H:%M')"
  echo "app        cpu% idlew power samples: $APP"
  echo "WindowServer cpu% idlew power samples: $WS"
  echo "assertions=$ASSERT listening=$LISTEN non-loopback-sockets=$NONLOOP child-processes=$CHILDREN"
} | tee "$OUT/summary.txt"

if [[ -s "$OUT/sample.txt" ]]; then
  echo "Hottest frames (sample):"
  # The heaviest call-graph lines, without the run-loop and thread plumbing.
  grep -E "^\s+[0-9]+ " "$OUT/sample.txt" | sort -k1 -nr | grep -vE "start|thread_start|_pthread|mach_msg|CFRunLoop|__CFRUNLOOP|NSApplication run|main \+" | head -15
fi
