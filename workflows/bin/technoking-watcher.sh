#!/usr/bin/env bash
# technoking-watcher.sh — fswatch wrapper feeding Technoking's wake channel.
#
# Watches .claude-team/inbox/. Each newly-created INBOX-*.json file path is
# appended to .claude-team/.runtime/wake.log. Technoking subscribes via:
#   Monitor(command: 'tail -F -n 0 .claude-team/.runtime/wake.log', persistent: true)
#
# Started by technoking-daemons.sh start; killed by stop. Long-running.
# macOS only (fswatch from `brew install fswatch`).

set -u
IFS=$'\n\t'

CLAUDE_TEAM_DIR="${CLAUDE_TEAM_DIR:-.claude-team}"
INBOX="${CLAUDE_TEAM_DIR}/inbox"
RUNTIME="${CLAUDE_TEAM_DIR}/.runtime"
WAKE_LOG="${RUNTIME}/wake.log"

mkdir -p "$INBOX" "$RUNTIME"
touch "$WAKE_LOG"

if ! command -v fswatch >/dev/null 2>&1; then
  echo "ERROR: fswatch not installed (brew install fswatch)" >&2
  exit 2
fi

# fswatch emits absolute paths on any FS event. Filter to INBOX-*.json so the
# wake.log stays clean (ignore directives, processed flag updates, etc.).
# --line-buffered keeps grep flushing per match instead of buffering 4 KB.
fswatch "$INBOX" 2>/dev/null \
  | grep --line-buffered -E '/INBOX-[^/]+\.json$' \
  >> "$WAKE_LOG"
