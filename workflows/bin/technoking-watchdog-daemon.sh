#!/usr/bin/env bash
# technoking-watchdog-daemon.sh — periodic stuck-worker detector.
#
# Every WATCHDOG_INTERVAL_S (default 40s), invokes ticket-watchdog.sh against
# every worker pane with --dispatch-surrogate. When stuck-pattern is detected
# (error_loop | rev_repeat | rev_idle), the watchdog itself writes
# INBOX-<ts>-<pane>.json + touches .runtime/<pane>.complete sentinel — and the
# fswatch watcher converts that inbox write into a Technoking wake event.
#
# Started by technoking-daemons.sh start; killed by stop. Long-running.

set -u
IFS=$'\n\t'

CLAUDE_TEAM_DIR="${CLAUDE_TEAM_DIR:-.claude-team}"
INTERVAL="${WATCHDOG_INTERVAL_S:-40}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WATCHDOG="${SCRIPT_DIR}/ticket-watchdog.sh"
REGISTRY="${CLAUDE_TEAM_DIR}/workers/registry.json"

if [[ ! -x "$WATCHDOG" ]]; then
  echo "ERROR: ticket-watchdog.sh not found at $WATCHDOG" >&2
  exit 2
fi

# All worker panes. ticket-watchdog.sh skips panes with no error/repeat/idle
# pattern, so iterating all 4 is cheap (~one tmux capture-pane per pane per cycle).
PANES=(worker-be worker-fe worker-qa worker-review)

while true; do
  if [[ -f "$REGISTRY" ]]; then
    for pane in "${PANES[@]}"; do
      "$WATCHDOG" "$pane" --dispatch-surrogate >/dev/null 2>&1 || true
    done
  fi
  sleep "$INTERVAL"
done
