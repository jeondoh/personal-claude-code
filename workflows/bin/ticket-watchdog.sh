#!/usr/bin/env bash
# ticket-watchdog.sh — surrogate stuck-pattern detector + verification phase for Technoking.
#
# Purpose: when a worker fails to self-escalate (its prompt has drifted under
# context pressure, or it is mis-following the §Escalation Conditions procedure),
# the watchdog collects external evidence, verifies whether the pattern is a
# real loop/stagnation, classifies it, and publishes the appropriate INBOX kind.
# Unlike v1 (immediate kill), v2 routes ambiguous cases through `pattern_question`
# so Technoking can present the evidence to the user before kill-and-rescue.
#
# Usage:
#   ticket-watchdog.sh <pane-name> [--dispatch-surrogate]
#
#   <pane-name>: worker-be | worker-fe | worker-qa | worker-review
#   --dispatch-surrogate: on classification, write the INBOX file (+ sentinel
#                         touch only for confirmed_loop / stagnation /
#                         protected_breach). Without the flag the script runs
#                         as a read-only probe and only prints its verdict.
#
# Exit codes:
#   0 = no stuck pattern OR worker is already self-escalating OR normal_thinking
#   1 = pattern classified (confirmed_loop | stagnation | protected_breach | ambiguous)
#   2 = pane not found / tmux capture failed
#
# Stdout: a single line of pseudo-JSON
#   {pane, ticket, verdict, signals: {names hit}, action, suggested_signature}
#
# Signals (any combination triggers verification phase):
#   1. error_loop          — same exception/error class N+ times in capture window
#   2. rev_repeat          — same non-empty line N+ times in capture window
#   3. rev_idle            — pane no activity > IDLE_THRESHOLD (default 480s)
#   4. last_update_stale   — ticket frontmatter last_update_at > STALE_THRESHOLD (default 600s)
#   5. protected_breach    — worktree diff touches a ticket-declared protected_files glob
#   6. worktree_stagnation — worktree last file mtime > STAGNATION_THRESHOLD (default 300s)
#
# Verification phase (when ≥1 signal fires):
#   - Deep tmux capture (default 600 lines)
#   - Worktree git diff / status / log analysis
#   - Ticket frontmatter parse
#   - Classify (priority order):
#       PROTECTED_BREACH > CONFIRMED_LOOP > STAGNATION > AMBIGUOUS > NORMAL
#   - Emit INBOX kind by class:
#       PROTECTED_BREACH → kind: escalation_needed (reason: protected_file_edit) + sentinel
#       CONFIRMED_LOOP   → kind: error_2x (verifier_verdict: confirmed_loop) + sentinel
#       STAGNATION       → kind: escalation_needed (reason: stagnation) + sentinel
#       AMBIGUOUS        → kind: pattern_question (no sentinel — keep worker alive)
#       NORMAL           → no INBOX, log only
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
IDLE_THRESHOLD_SECONDS="${WATCHDOG_IDLE_SECONDS:-480}"           # 8 min
STALE_THRESHOLD_SECONDS="${WATCHDOG_STALE_SECONDS:-600}"         # 10 min — last_update_at
STAGNATION_THRESHOLD_SECONDS="${WATCHDOG_STAGNATION_SECONDS:-300}" # 5 min — worktree mtime
REPEAT_THRESHOLD="${WATCHDOG_REPEAT_THRESHOLD:-3}"
CAPTURE_LINES="${WATCHDOG_CAPTURE_LINES:-300}"
VERIFY_CAPTURE_LINES="${WATCHDOG_VERIFY_CAPTURE_LINES:-600}"

if [[ ! -f "$REGISTRY" ]]; then
  echo "registry.json not found at $REGISTRY" >&2
  exit 2
fi

# Resolve pane_id from registry.json
PANE_ID=$(grep -A3 "\"$PANE_NAME\"" "$REGISTRY" 2>/dev/null \
  | grep -m1 '"pane_id"' \
  | cut -d'"' -f4)
if [[ -z "$PANE_ID" ]]; then
  echo "pane_id not found for $PANE_NAME" >&2
  exit 2
fi

# Locate this pane's in-progress ticket (if any)
TICKET_FILE=$(ls "${CLAUDE_TEAM_DIR}/tickets/in-progress/"*.md 2>/dev/null | head -1)
TICKET_ID=""
TICKET_OWNER=""
WORKTREE_PATH=""
LAST_UPDATE_AT=""
PROTECTED_FILES=()

if [[ -n "$TICKET_FILE" ]]; then
  # Walk every in-progress ticket; pick the one whose worker/owner matches this pane's persona
  EXPECTED_PERSONA=""
  case "$PANE_NAME" in
    worker-be)     EXPECTED_PERSONA="persistence-paladin" ;;
    worker-fe)     EXPECTED_PERSONA="pixel-wizard" ;;
    worker-qa)     EXPECTED_PERSONA="what-if-witch" ;;
    worker-review) EXPECTED_PERSONA="the-roastmaster" ;;
  esac
  for f in "${CLAUDE_TEAM_DIR}/tickets/in-progress/"*.md; do
    [[ -f "$f" ]] || continue
    # skip finished/escalated tickets lingering in in-progress/ (worker forgot mv)
    if grep -q "owner: $EXPECTED_PERSONA\|worker: $EXPECTED_PERSONA\|assignee: $EXPECTED_PERSONA" "$f" 2>/dev/null \
       && grep -qE "^status:[[:space:]]*(in_progress|claimed)\$" "$f" 2>/dev/null; then
      TICKET_FILE="$f"
      TICKET_ID=$(grep '^id:' "$f" | head -1 | awk '{print $2}')
      TICKET_OWNER="$EXPECTED_PERSONA"
      LAST_UPDATE_AT=$(grep '^last_update_at:' "$f" | head -1 | sed 's/^last_update_at:[[:space:]]*//')
      # Parse protected_files list (YAML array — naive)
      while IFS= read -r line; do
        PROTECTED_FILES+=("$line")
      done < <(awk '/^protected_files:/,/^[^[:space:]-]/' "$f" 2>/dev/null \
        | grep -E '^\s*-\s*' | sed -E 's/^\s*-\s*//' | head -20)
      WORKTREE_PATH=".worktrees/${TICKET_ID}"
      [[ ! -d "$WORKTREE_PATH" ]] && WORKTREE_PATH=$(ls -d ".worktrees/${TICKET_ID}-"* 2>/dev/null | head -1)
      break
    fi
  done
fi

# Capture recent pane output
CAPTURE=$(tmux capture-pane -t "$PANE_ID" -p -S "-${CAPTURE_LINES}" 2>/dev/null) || {
  echo "tmux capture failed for $PANE_ID" >&2
  exit 2
}

# Early skip: self-escalation already in flight
if grep -qE 'error_2x|escalation_needed|pattern_stuck|rescue_candidate' <<<"$CAPTURE"; then
  echo "{\"pane\":\"$PANE_NAME\",\"verdict\":\"self_escalated\",\"action\":\"skip\"}"
  exit 0
fi

# Early skip: no in-progress ticket for this pane → pane is idle polling,
# any pattern in the capture is leftover text from a finished ticket.
# Without an active ticket there is no work to be stuck on.
if [[ -z "$TICKET_ID" ]]; then
  echo "{\"pane\":\"$PANE_NAME\",\"verdict\":\"idle_no_ticket\",\"action\":\"skip\"}"
  exit 0
fi

# Early skip: no live claude under pane shell → idle polling with stale ticket file
SHELL_PID=$(tmux display-message -t "$PANE_ID" -p '#{pane_pid}' 2>/dev/null)
CLAUDE_ALIVE=0
if [[ -n "$SHELL_PID" ]]; then
  pgrep -P "$SHELL_PID" -f 'claude' >/dev/null 2>&1 && CLAUDE_ALIVE=1
fi
if [[ "$CLAUDE_ALIVE" -eq 0 ]]; then
  echo "{\"pane\":\"$PANE_NAME\",\"verdict\":\"claude_idle\",\"action\":\"skip\"}"
  exit 0
fi

# ── Signal collection ────────────────────────────────────────────────
NOW=$(date +%s)
SIGNALS=()

# Signal 1: error_loop
ERR_LINE=$(grep -oE '[A-Z][A-Za-z]+(Exception|Error)' <<<"$CAPTURE" | sort | uniq -c | sort -rn | head -1)
ERR_COUNT=$(awk '{print $1}' <<<"$ERR_LINE")
ERR_CLASS=$(awk '{print $2}' <<<"$ERR_LINE")
if [[ -n "$ERR_COUNT" && "$ERR_COUNT" -ge "$REPEAT_THRESHOLD" ]]; then
  SIGNALS+=("error_loop:${ERR_CLASS}:${ERR_COUNT}")
fi

# Signal 2: rev_repeat
REPEAT_LINE=$(awk 'NF' <<<"$CAPTURE" | sort | uniq -c | sort -rn | head -1)
REPEAT_COUNT=$(awk '{print $1}' <<<"$REPEAT_LINE")
if [[ -n "$REPEAT_COUNT" && "$REPEAT_COUNT" -ge "$REPEAT_THRESHOLD" ]]; then
  SIGNALS+=("rev_repeat:${REPEAT_COUNT}")
fi

# Signal 3: rev_idle
LAST_ACTIVITY=$(tmux display-message -t "$PANE_ID" -p '#{pane_activity}' 2>/dev/null)
IDLE_AGE=0
if [[ -n "$LAST_ACTIVITY" && "$LAST_ACTIVITY" =~ ^[0-9]+$ ]]; then
  IDLE_AGE=$(( NOW - LAST_ACTIVITY ))
fi
if [[ "$IDLE_AGE" -ge "$IDLE_THRESHOLD_SECONDS" ]]; then
  SIGNALS+=("rev_idle:${IDLE_AGE}s")
fi

# Signal 4: last_update_stale (ticket frontmatter)
STALE_AGE=0
if [[ -n "$LAST_UPDATE_AT" ]]; then
  # Parse ISO 8601 with +09:00 offset
  LAST_UPDATE_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%S%z" "$LAST_UPDATE_AT" +%s 2>/dev/null) \
    || LAST_UPDATE_EPOCH=$(date -d "$LAST_UPDATE_AT" +%s 2>/dev/null) \
    || LAST_UPDATE_EPOCH=0
  if [[ "$LAST_UPDATE_EPOCH" -gt 0 ]]; then
    STALE_AGE=$(( NOW - LAST_UPDATE_EPOCH ))
    if [[ "$STALE_AGE" -ge "$STALE_THRESHOLD_SECONDS" ]]; then
      SIGNALS+=("last_update_stale:${STALE_AGE}s")
    fi
  fi
fi

# Signal 5: protected_breach (worktree diff matches protected_files glob)
PROTECTED_HIT=""
if [[ -n "$WORKTREE_PATH" && -d "$WORKTREE_PATH" && ${#PROTECTED_FILES[@]} -gt 0 ]]; then
  CHANGED_FILES=$(cd "$WORKTREE_PATH" 2>/dev/null && git diff --name-only HEAD 2>/dev/null)
  if [[ -n "$CHANGED_FILES" ]]; then
    while IFS= read -r changed; do
      for glob in "${PROTECTED_FILES[@]}"; do
        # Naive glob match: replace ** with .* and * with [^/]*
        pattern=$(echo "$glob" | sed 's|\*\*|.*|g; s|\*|[^/]*|g')
        if [[ "$changed" =~ ^${pattern}$ ]]; then
          PROTECTED_HIT="${changed}<-${glob}"
          break 2
        fi
      done
    done <<<"$CHANGED_FILES"
  fi
fi
if [[ -n "$PROTECTED_HIT" ]]; then
  SIGNALS+=("protected_breach:${PROTECTED_HIT}")
fi

# Signal 6: worktree_stagnation (no file change for N min)
STAGNATION_AGE=0
if [[ -n "$WORKTREE_PATH" && -d "$WORKTREE_PATH" ]]; then
  # Most recent mtime in worktree (skip .git)
  LATEST_MTIME=$(find "$WORKTREE_PATH" -type f -not -path '*/.git/*' -exec stat -f '%m' {} + 2>/dev/null | sort -rn | head -1)
  if [[ -n "$LATEST_MTIME" ]]; then
    STAGNATION_AGE=$(( NOW - LATEST_MTIME ))
    if [[ "$STAGNATION_AGE" -ge "$STAGNATION_THRESHOLD_SECONDS" ]]; then
      SIGNALS+=("worktree_stagnation:${STAGNATION_AGE}s")
    fi
  fi
fi

SIGNAL_COUNT=${#SIGNALS[@]}
SIGNAL_JOINED=$(IFS=','; echo "${SIGNALS[*]}")

# No signals — clean
if [[ "$SIGNAL_COUNT" -eq 0 ]]; then
  echo "{\"pane\":\"$PANE_NAME\",\"ticket\":\"${TICKET_ID}\",\"verdict\":\"none\",\"signals\":[],\"idle_age_s\":$IDLE_AGE,\"stale_age_s\":$STALE_AGE,\"stagnation_age_s\":$STAGNATION_AGE}"
  exit 0
fi

# ── Verification phase ────────────────────────────────────────────────
# Priority order: PROTECTED_BREACH > CONFIRMED_LOOP > STAGNATION > AMBIGUOUS > NORMAL

VERDICT=""
SUGGESTED_KIND=""
SUGGESTED_REASON=""
TOUCH_SENTINEL=0

# Deep capture for verification
DEEP_CAPTURE=$(tmux capture-pane -t "$PANE_ID" -p -S "-${VERIFY_CAPTURE_LINES}" 2>/dev/null)

# Rule 1: PROTECTED_BREACH — strong signal, immediate
if [[ -n "$PROTECTED_HIT" ]]; then
  VERDICT="protected_breach"
  SUGGESTED_KIND="escalation_needed"
  SUGGESTED_REASON="protected_file_edit:${PROTECTED_HIT}"
  TOUCH_SENTINEL=1

# Rule 2: CONFIRMED_LOOP — error_loop OR rev_repeat + (last_update_stale OR worktree_stagnation)
#         i.e. repeating output AND no real progress
elif [[ ("$ERR_COUNT" -ge "$REPEAT_THRESHOLD" || "$REPEAT_COUNT" -ge "$REPEAT_THRESHOLD") \
       && ("$STALE_AGE" -ge "$STALE_THRESHOLD_SECONDS" || "$STAGNATION_AGE" -ge "$STAGNATION_THRESHOLD_SECONDS") ]]; then
  VERDICT="confirmed_loop"
  SUGGESTED_KIND="error_2x"
  TOUCH_SENTINEL=1

# Rule 3: STAGNATION — rev_idle + (last_update_stale OR worktree_stagnation), no error churn
elif [[ "$IDLE_AGE" -ge "$IDLE_THRESHOLD_SECONDS" \
       && ("$STALE_AGE" -ge "$STALE_THRESHOLD_SECONDS" || "$STAGNATION_AGE" -ge "$STAGNATION_THRESHOLD_SECONDS") ]]; then
  VERDICT="stagnation"
  SUGGESTED_KIND="escalation_needed"
  SUGGESTED_REASON="stagnation:idle=${IDLE_AGE}s,stale=${STALE_AGE}s,stagnation=${STAGNATION_AGE}s"
  TOUCH_SENTINEL=1

# Rule 4: AMBIGUOUS — live claude + single signal → likely noise; no INBOX, keep worker alive
elif [[ "$SIGNAL_COUNT" -ge 1 ]]; then
  VERDICT="ambiguous"
  SUGGESTED_KIND=""
  TOUCH_SENTINEL=0

# Rule 5: NORMAL — should not reach here, but defensive
else
  VERDICT="normal_thinking"
  SUGGESTED_KIND=""
fi

# Best-effort signature
SIG="surrogate-$(printf '%s:%s:%s' "${ERR_CLASS:-unknown}" "$PANE_NAME" "$VERDICT" | sha1sum | cut -c1-8)"

OUT="{\"pane\":\"$PANE_NAME\",\"ticket\":\"${TICKET_ID}\",\"verdict\":\"$VERDICT\",\"signals\":[\"${SIGNAL_JOINED//,/\",\"}\"],\"err_class\":\"${ERR_CLASS:-}\",\"err_count\":${ERR_COUNT:-0},\"repeat_count\":${REPEAT_COUNT:-0},\"idle_age_s\":$IDLE_AGE,\"stale_age_s\":$STALE_AGE,\"stagnation_age_s\":$STAGNATION_AGE,\"protected_hit\":\"${PROTECTED_HIT}\",\"suggested_kind\":\"$SUGGESTED_KIND\",\"suggested_signature\":\"$SIG\",\"sentinel\":${TOUCH_SENTINEL}}"
echo "$OUT"

# ── Dispatch ─────────────────────────────────────────────────────────
if [[ "$DISPATCH_FLAG" != "--dispatch-surrogate" || -z "$SUGGESTED_KIND" ]]; then
  exit 1
fi

INBOX_TS=$(TZ=Asia/Seoul date +'%Y%m%dT%H%M%S+0900')
INBOX_FILE="${CLAUDE_TEAM_DIR}/inbox/INBOX-${INBOX_TS}-${PANE_NAME}.json"
EVIDENCE_LOG="${CLAUDE_TEAM_DIR}/.runtime/verifier-${INBOX_TS}-${PANE_NAME}.log"
mkdir -p "${CLAUDE_TEAM_DIR}/inbox" "${CLAUDE_TEAM_DIR}/.runtime"

# Dump evidence (sanitized) — Technoking attaches when escalating to user
{
  echo "=== watchdog verifier evidence — $INBOX_TS ==="
  echo "pane: $PANE_NAME"
  echo "ticket: $TICKET_ID"
  echo "verdict: $VERDICT"
  echo "signals: $SIGNAL_JOINED"
  echo ""
  echo "=== last 60 lines of pane ==="
  tail -60 <<<"$DEEP_CAPTURE"
  if [[ -n "$WORKTREE_PATH" && -d "$WORKTREE_PATH" ]]; then
    echo ""
    echo "=== worktree git status -s ==="
    (cd "$WORKTREE_PATH" && git status -s) 2>/dev/null | head -40
    echo ""
    echo "=== worktree git diff --stat ==="
    (cd "$WORKTREE_PATH" && git diff --stat HEAD) 2>/dev/null | head -40
  fi
} > "$EVIDENCE_LOG"

# INBOX payload — kind-specific
case "$SUGGESTED_KIND" in
  error_2x)
    cat > "$INBOX_FILE" <<EOF
{ "kind": "error_2x", "from": "technoking-watchdog", "to": "technoking", "pane": "${PANE_NAME}", "ticket": "${TICKET_ID}", "verifier_verdict": "${VERDICT}", "signals": ["${SIGNAL_JOINED//,/\",\"}"], "error_signature": "${SIG}", "err_class": "${ERR_CLASS:-}", "repeat_count": ${REPEAT_COUNT:-0}, "idle_age_s": ${IDLE_AGE}, "stale_age_s": ${STALE_AGE}, "stagnation_age_s": ${STAGNATION_AGE}, "evidence_dump_path": "${EVIDENCE_LOG}" }
EOF
    ;;
  escalation_needed)
    cat > "$INBOX_FILE" <<EOF
{ "kind": "escalation_needed", "from": "technoking-watchdog", "to": "technoking", "pane": "${PANE_NAME}", "ticket": "${TICKET_ID}", "verifier_verdict": "${VERDICT}", "reason": "${SUGGESTED_REASON}", "signals": ["${SIGNAL_JOINED//,/\",\"}"], "idle_age_s": ${IDLE_AGE}, "stale_age_s": ${STALE_AGE}, "stagnation_age_s": ${STAGNATION_AGE}, "protected_hit": "${PROTECTED_HIT}", "evidence_dump_path": "${EVIDENCE_LOG}" }
EOF
    ;;
  pattern_question)
    cat > "$INBOX_FILE" <<EOF
{ "kind": "pattern_question", "from": "technoking-watchdog", "to": "technoking", "pane": "${PANE_NAME}", "ticket": "${TICKET_ID}", "verifier_verdict": "ambiguous", "signals": ["${SIGNAL_JOINED//,/\",\"}"], "idle_age_s": ${IDLE_AGE}, "stale_age_s": ${STALE_AGE}, "stagnation_age_s": ${STAGNATION_AGE}, "recommended_action": "user_decide", "evidence_dump_path": "${EVIDENCE_LOG}" }
EOF
    ;;
esac

# Sentinel touch ONLY for confirmed states (protected_breach, confirmed_loop, stagnation)
# AMBIGUOUS → no sentinel → worker keeps running until user decides
if [[ "$TOUCH_SENTINEL" -eq 1 ]]; then
  touch "${CLAUDE_TEAM_DIR}/.runtime/${PANE_NAME}.complete"
  echo "{\"surrogate_inbox\":\"$INBOX_FILE\",\"sentinel\":\"${CLAUDE_TEAM_DIR}/.runtime/${PANE_NAME}.complete\",\"evidence\":\"$EVIDENCE_LOG\"}"
else
  echo "{\"surrogate_inbox\":\"$INBOX_FILE\",\"sentinel\":\"NONE-ambiguous\",\"evidence\":\"$EVIDENCE_LOG\"}"
fi

exit 1
