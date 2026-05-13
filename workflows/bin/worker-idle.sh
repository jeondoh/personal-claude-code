#!/usr/bin/env bash
# worker-idle.sh — pure-shell polling loop for a worker pane.
#
# Architecture (2-stage launch):
#   1. Worker pane starts this script — no claude session, just shell.
#   2. Script silently polls .claude-team/tickets/queue/ every 30s.
#   3. When a ticket is claimed, script execs `claude` with the ticket as
#      the first message (the persona system prompt is loaded from a file).
#   4. claude is told (via system prompt addendum) to `touch <SENTINEL>` as
#      its final Bash call after posting the completion/escalation inbox
#      message. A watchdog in this script sees the sentinel, kills claude,
#      and the loop resumes polling.
#
# Why 2-stage: keeps the pane chat log clean during idle — only a few short
# log lines, no Bash tool UI clutter. Cost: zero tokens during idle (vs.
# claude-as-poller which spends a few hundred tokens per 5-min cycle).
#
# Usage: worker-idle.sh <persona-slug> <pane-name> <abs-prompt-file>
# Run by: worker-launch.sh (via tmux send-keys)
# Termination: SIGINT/SIGTERM from outside; never exits voluntarily.

set -u
IFS=$'\n\t'

SLUG="$1"
PANE_NAME="$2"
PROMPT_FILE="$3"

CLAUDE_TEAM_DIR="${CLAUDE_TEAM_DIR:-.claude-team}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
AGENTS_DIR="${PLUGIN_ROOT}/agents"
PERSONA_FILE="${AGENTS_DIR}/${SLUG}.md"

# ---------- helpers ----------------------------------------------------------

fm_field() {
  grep -m1 "^${2}:" "$1" 2>/dev/null | cut -d':' -f2- | sed 's/^ *//' | sed 's/^"//;s/"$//' | sed "s/^'//;s/'\$//"
}

ts() { TZ=Asia/Seoul date +'%H:%M:%S'; }

# ---------- read persona frontmatter -----------------------------------------

GREETING="$(fm_field "$PERSONA_FILE" idle_greeting)"
[[ -z "$GREETING" ]] && GREETING="[${SLUG}] 가동. ticket 대기 중."

MODEL="$(fm_field "$PERSONA_FILE" model)"
[[ -z "$MODEL" ]] && MODEL="sonnet"

SENTINEL_DIR="${CLAUDE_TEAM_DIR}/.runtime"
SENTINEL="${SENTINEL_DIR}/${PANE_NAME}.complete"
mkdir -p "$SENTINEL_DIR"
# 절대 경로 변환
case "$SENTINEL" in
  /*) ABS_SENTINEL="$SENTINEL" ;;
   *) ABS_SENTINEL="$(pwd)/$SENTINEL" ;;
esac

# ---------- greeting ---------------------------------------------------------

clear 2>/dev/null || true
printf '%s\n\n' "$GREETING"
printf '폴링 중. 큐에 ticket 이 들어오면 자동으로 claude 가 발화한다.\n'
printf '────────────────────────────────────────\n'

# ---------- main loop --------------------------------------------------------

while true; do
  out=$(ticket-poll.sh "$SLUG" 2>&1) || {
    printf '[%s] poll error: %s — 30s 후 재시도\n' "$(ts)" "$out"
    sleep 30
    continue
  }

  case "$out" in
    none:*)
      sleep 30
      ;;
    queue*for*)
      # Ticket available — claim and find it.
      printf '[%s] %s\n' "$(ts)" "$out"
      claim_out=$(ticket-poll.sh "$SLUG" --claim 2>&1) || {
        printf '[%s] claim 실패: %s\n' "$(ts)" "$claim_out"
        sleep 30
        continue
      }
      printf '[%s] %s\n' "$(ts)" "$claim_out"

      # Find the most recently claimed ticket for this worker.
      shopt -s nullglob 2>/dev/null || true
      ticket_files=( "${CLAUDE_TEAM_DIR}"/tickets/in-progress/T-*.md "${CLAUDE_TEAM_DIR}"/tickets/in-progress/RV-*.md )
      shopt -u nullglob 2>/dev/null || true

      ticket_file=""
      for f in "${ticket_files[@]}"; do
        # Pick the one whose `owner` field matches this slug.
        if grep -q "^owner: *${SLUG}\$" "$f" 2>/dev/null; then
          if [[ -z "$ticket_file" || "$f" -nt "$ticket_file" ]]; then
            ticket_file="$f"
          fi
        fi
      done

      if [[ -z "$ticket_file" ]]; then
        printf '[%s] 클레임 후 ticket 파일을 못 찾음 — 30s 후 재시도\n' "$(ts)"
        sleep 30
        continue
      fi

      printf '[%s] 작업 시작: %s\n' "$(ts)" "$ticket_file"
      printf '────────────────────────────────────────\n\n'

      rm -f "$SENTINEL"

      # First message tells claude exactly what to do + how to end.
      first_msg=$(cat <<EOMSG
You have just claimed ticket file: ${ticket_file}

Read CLAUDE.md, your persona file (${PERSONA_FILE}), the ticket frontmatter + body, and your assigned skills. Then execute the ticket per ticket-protocol.

When the ticket is fully done (PR pushed + completion inbox message written), OR when you have escalated via an inbox message (kind: escalation_needed / error_2x / pattern_stuck / etc.), your LAST action MUST be exactly:

  Bash: touch ${ABS_SENTINEL}

After that, do NOT continue. The shell watchdog in this pane will see the sentinel and end this Claude session, returning the pane to idle polling.

Do not skip the sentinel step — without it the worker pane stays blocked on this ticket forever.
EOMSG
)

      claude --dangerously-skip-permissions \
        --model "$MODEL" \
        --append-system-prompt-file "$PROMPT_FILE" \
        "$first_msg" &
      CLAUDE_PID=$!
      TICKET_TIMEOUT="${CLAUDE_TEAM_TICKET_TIMEOUT:-1800}"
      START_TS=$(date +%s)

      # Watchdog: poll for sentinel, claude dying, or timeout.
      while kill -0 "$CLAUDE_PID" 2>/dev/null; do
        if [[ -f "$SENTINEL" ]]; then
          sleep 2
          kill -INT "$CLAUDE_PID" 2>/dev/null || true
          sleep 3
          kill -0 "$CLAUDE_PID" 2>/dev/null && kill -TERM "$CLAUDE_PID" 2>/dev/null
          break
        fi
        ELAPSED=$(( $(date +%s) - START_TS ))
        if [[ $ELAPSED -ge $TICKET_TIMEOUT ]]; then
          printf '[%s] ticket timeout (%ds) — claude 강제 종료\n' "$(ts)" "$ELAPSED"
          INBOX_TS=$(TZ=Asia/Seoul date +'%Y%m%dT%H%M%S+0900')
          cat > "${CLAUDE_TEAM_DIR}/inbox/INBOX-${INBOX_TS}-${PANE_NAME}.json" <<EOF
{ "kind": "escalation_needed", "reason": "ticket_timeout", "pane": "${PANE_NAME}", "elapsed_seconds": ${ELAPSED}, "ticket_file": "${ticket_file}" }
EOF
          kill -TERM "$CLAUDE_PID" 2>/dev/null || true
          sleep 2
          kill -KILL "$CLAUDE_PID" 2>/dev/null || true
          break
        fi
        sleep 3
      done
      wait "$CLAUDE_PID" 2>/dev/null
      rm -f "$SENTINEL"

      END_TS=$(date +%s)
      DURATION=$(( END_TS - START_TS ))
      if [[ $DURATION -lt 10 ]]; then
        printf '[%s] claude 가 %ds 만에 종료됨 — 60s 백오프\n' "$(ts)" "$DURATION"
        sleep 60
      fi

      printf '\n────────────────────────────────────────\n'
      printf '[%s] ticket 종료. 폴링 재개.\n\n' "$(ts)"
      ;;
    *)
      printf '[%s] 예상 못한 출력: %s\n' "$(ts)" "$out"
      sleep 30
      ;;
  esac
done
