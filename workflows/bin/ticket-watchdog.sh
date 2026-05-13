#!/usr/bin/env bash
# ticket-watchdog.sh — surrogate stuck-pattern detector for Technoking.
#
# Purpose: when a worker fails to self-escalate (e.g., its prompt has drifted
# under context pressure and the §Escalation Conditions §1 procedure is being
# skipped), Technoking inspects the worker pane's recent output, detects a
# "stuck" pattern, and optionally publishes a surrogate INBOX message plus a
# forced idle-reset (touch .runtime/<pane>.complete).
#
# Usage:
#   ticket-watchdog.sh <pane-name> [--dispatch-surrogate]
#
#   <pane-name>: worker-be | worker-fe | worker-qa | worker-review
#   --dispatch-surrogate: on detection, write the INBOX file and touch the
#                         sentinel. Without the flag the script runs as a
#                         read-only probe and only prints its verdict.
#
# Exit codes:
#   0 = no stuck pattern (normal) or worker is already self-escalating
#   1 = stuck pattern detected (error_loop | rev_repeat | rev_idle)
#   2 = pane not found / tmux capture failed
#
# Stdout: a single line of pseudo-JSON
#   {pane, pattern, err_class, err_count, repeat_count, idle_age_s,
#    suggested_signature}
#
# Detection patterns (any one triggers stuck = exit 1):
#   1. error_loop — the same exception/error class appears N+ times in the
#      capture window.
#   2. rev_repeat — the same non-empty line appears N+ times (indicating a
#      build/test command being re-run with no progress).
#   3. rev_idle   — the pane has had no activity for more than N seconds
#      (default 480 = 8 min) per tmux's #{pane_activity}.
#
# If the capture window already contains the worker's own escalation markers
# (error_2x | escalation_needed | pattern_stuck | rescue_candidate) the
# watchdog yields (exit 0) — self-escalation is already in progress.

set -u
IFS=$'\n\t'

PANE_NAME="${1:-}"
DISPATCH_FLAG="${2:-}"

if [[ -z "$PANE_NAME" ]]; then
  echo "usage: ticket-watchdog.sh <pane-name> [--dispatch-surrogate]" >&2
  exit 2
fi

CLAUDE_TEAM_DIR="${CLAUDE_TEAM_DIR:-.claude-team}"
REGISTRY="${CLAUDE_TEAM_DIR}/workers/registry.json"
IDLE_THRESHOLD_SECONDS="${WATCHDOG_IDLE_SECONDS:-480}"      # 8 min default
REPEAT_THRESHOLD="${WATCHDOG_REPEAT_THRESHOLD:-3}"
CAPTURE_LINES="${WATCHDOG_CAPTURE_LINES:-300}"

if [[ ! -f "$REGISTRY" ]]; then
  echo "registry.json not found at $REGISTRY" >&2
  exit 2
fi

# Resolve pane_id from registry.json (key = pane name).
PANE_ID=$(grep -A3 "\"$PANE_NAME\"" "$REGISTRY" 2>/dev/null \
  | grep -m1 '"pane_id"' \
  | cut -d'"' -f4)

if [[ -z "$PANE_ID" ]]; then
  echo "pane_id not found for $PANE_NAME" >&2
  exit 2
fi

# Capture recent pane output.
CAPTURE=$(tmux capture-pane -t "$PANE_ID" -p -S "-${CAPTURE_LINES}" 2>/dev/null) || {
  echo "tmux capture failed for $PANE_ID" >&2
  exit 2
}

# Early skip: if the worker already shows self-escalation markers, the normal
# rescue path is in flight — do not double-dispatch.
if grep -qE 'error_2x|escalation_needed|pattern_stuck|rescue_candidate' <<<"$CAPTURE"; then
  echo "{\"pane\":\"$PANE_NAME\",\"pattern\":\"self_escalated\",\"action\":\"skip\"}"
  exit 0
fi

# Pattern 1: error_loop — same exception class repeated.
ERR_LINE=$(grep -oE '[A-Z][A-Za-z]+(Exception|Error)' <<<"$CAPTURE" \
  | sort | uniq -c | sort -rn | head -1)
ERR_COUNT=$(awk '{print $1}' <<<"$ERR_LINE")
ERR_CLASS=$(awk '{print $2}' <<<"$ERR_LINE")

# Pattern 2: rev_repeat — same non-empty line repeated.
REPEAT_LINE=$(awk 'NF' <<<"$CAPTURE" | sort | uniq -c | sort -rn | head -1)
REPEAT_COUNT=$(awk '{print $1}' <<<"$REPEAT_LINE")

# Pattern 3: rev_idle — pane has been quiet for too long.
LAST_ACTIVITY=$(tmux display-message -t "$PANE_ID" -p '#{pane_activity}' 2>/dev/null)
NOW=$(date +%s)
if [[ -n "$LAST_ACTIVITY" && "$LAST_ACTIVITY" =~ ^[0-9]+$ ]]; then
  IDLE_AGE=$(( NOW - LAST_ACTIVITY ))
else
  IDLE_AGE=0
fi

PATTERN=""
if [[ -n "$ERR_COUNT" && "$ERR_COUNT" -ge "$REPEAT_THRESHOLD" ]]; then
  PATTERN="error_loop"
elif [[ -n "$REPEAT_COUNT" && "$REPEAT_COUNT" -ge "$REPEAT_THRESHOLD" ]]; then
  PATTERN="rev_repeat"
elif [[ "$IDLE_AGE" -ge "$IDLE_THRESHOLD_SECONDS" ]]; then
  PATTERN="rev_idle"
fi

if [[ -z "$PATTERN" ]]; then
  echo "{\"pane\":\"$PANE_NAME\",\"pattern\":\"none\",\"err_count\":${ERR_COUNT:-0},\"repeat_count\":${REPEAT_COUNT:-0},\"idle_age_s\":$IDLE_AGE}"
  exit 0
fi

# Suggested signature — best-effort hint for Technoking's rescue dispatch.
SIG="surrogate-$(printf '%s:%s' "${ERR_CLASS:-unknown}" "$PANE_NAME" | sha1sum | cut -c1-8)"

OUT="{\"pane\":\"$PANE_NAME\",\"pattern\":\"$PATTERN\",\"err_class\":\"${ERR_CLASS:-}\",\"err_count\":${ERR_COUNT:-0},\"repeat_count\":${REPEAT_COUNT:-0},\"idle_age_s\":$IDLE_AGE,\"suggested_signature\":\"$SIG\"}"
echo "$OUT"

# Optional: publish surrogate INBOX + force idle reset.
if [[ "$DISPATCH_FLAG" == "--dispatch-surrogate" ]]; then
  INBOX_TS=$(TZ=Asia/Seoul date +'%Y%m%dT%H%M%S+0900')
  INBOX_FILE="${CLAUDE_TEAM_DIR}/inbox/INBOX-${INBOX_TS}-${PANE_NAME}.json"
  mkdir -p "${CLAUDE_TEAM_DIR}/inbox"
  cat > "$INBOX_FILE" <<EOF
{ "kind": "error_2x", "from": "technoking-watchdog", "to": "technoking", "pane": "${PANE_NAME}", "reason": "surrogate_pattern_detected:${PATTERN}", "error_signature": "${SIG}", "err_class": "${ERR_CLASS:-}", "rev_count": ${REPEAT_COUNT:-0}, "idle_age_s": ${IDLE_AGE} }
EOF
  # Force idle reset: worker-idle.sh's watchdog sees the sentinel and SIGINTs
  # the claude session, returning the pane to its polling loop.
  mkdir -p "${CLAUDE_TEAM_DIR}/.runtime"
  touch "${CLAUDE_TEAM_DIR}/.runtime/${PANE_NAME}.complete"
  echo "{\"surrogate_inbox\":\"$INBOX_FILE\",\"sentinel\":\"${CLAUDE_TEAM_DIR}/.runtime/${PANE_NAME}.complete\"}"
fi

exit 1
