#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Launch the claude-team tmux session: 5 panes (main + 4 workers), all rooted
# at the user's current working directory. main pane runs Technoking
# interactively; worker panes run silent polling claude instances.
#
# Layout (matches README):
#   ┌──────────────┬──────────────┐
#   │              │ worker-fe    │   pane 2 (top-right)
#   │              ├──────────────┤
#   │ main         │ worker-be    │   pane 3 (mid-right)
#   │ pane 0       ├──────────────┤
#   │ (top-left)   │ worker-qa    │   pane 4 (bottom-right)
#   ├──────────────┤              │
#   │ worker-review│              │
#   │ pane 1       │              │
#   └──────────────┴──────────────┘
#
#   team.0  main           Technoking
#   team.1  worker-review  The Roastmaster
#   team.2  worker-fe      Pixel Wizard
#   team.3  worker-be      Persistence Paladin
#   team.4  worker-qa      What-If Witch
#
# Usage: tmux-setup.sh [--session-name <name>]
# Exit codes: 0=ok, 1=generic fail, 2=preflight fail

CLAUDE_TEAM_DIR="${CLAUDE_TEAM_DIR:-.claude-team}"
SESSION_NAME="claude-team"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAUNCH_SCRIPT="${SCRIPT_DIR}/worker-launch.sh"
USER_PWD="$(pwd)"

# --- Parse args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --session-name) SESSION_NAME="$2"; shift 2 ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 1 ;;
  esac
done

# --- Pre-flight ---
if ! command -v tmux &>/dev/null; then
  echo "ERROR: tmux not found. Install tmux >= 3.2 before running /setup-team." >&2
  exit 2
fi
if ! command -v claude &>/dev/null; then
  echo "ERROR: claude CLI not found. Install Claude Code before running /setup-team." >&2
  exit 2
fi
if [[ ! -f "${CLAUDE_TEAM_DIR}/config.yml" ]]; then
  echo "ERROR: ${CLAUDE_TEAM_DIR}/config.yml 없음 — /setup-team 을 먼저 실행해라." >&2
  exit 2
fi
if [[ ! -x "${LAUNCH_SCRIPT}" ]]; then
  echo "ERROR: worker-launch.sh not found or not executable at ${LAUNCH_SCRIPT}" >&2
  exit 2
fi

# --- Idempotent session guard ---
# When called from inside an existing tmux session, attaching nested fails.
# Print attach hint and exit success.
if tmux has-session -t "${SESSION_NAME}" 2>/dev/null; then
  echo "Session '${SESSION_NAME}' 존재 — 페인 liveness 확인 중."
  RESTARTED=0
  for pane_idx in 0 1 2 3 4; do
    case "$pane_idx" in
      0) persona="technoking";          pane_name="main"          ;;
      1) persona="the-roastmaster";     pane_name="worker-review" ;;
      2) persona="pixel-wizard";        pane_name="worker-fe"     ;;
      3) persona="persistence-paladin"; pane_name="worker-be"     ;;
      4) persona="what-if-witch";       pane_name="worker-qa"     ;;
    esac
    tgt="${SESSION_NAME}:team.${pane_idx}"
    pid="$(tmux display-message -t "$tgt" -p '#{pane_pid}' 2>/dev/null)" || continue
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "  pane ${pane_name} 죽음 — 재시작."
      "${LAUNCH_SCRIPT}" "${tgt}" "${persona}" "${pane_name}" || echo "  WARN: ${pane_name} 재시작 실패"
      RESTARTED=$(( RESTARTED + 1 ))
    fi
  done
  if [[ $RESTARTED -eq 0 ]]; then
    echo "모든 페인 alive — 변경 없음."
  else
    echo "${RESTARTED}개 페인 재시작."
  fi
  if [[ -n "${TMUX:-}" ]]; then
    echo "Switch from inside tmux:  tmux switch-client -t ${SESSION_NAME}"
  else
    echo "Attach with:  tmux attach -t ${SESSION_NAME}"
  fi
  exit 0
fi

# --- Create session at USER_PWD so all panes inherit the user's cwd ---
tmux new-session -d -s "${SESSION_NAME}" -n team -c "${USER_PWD}"
tmux select-pane -t "${SESSION_NAME}:team.0" -T "main (Technoking)"

# --- Build layout (two independent columns) ---
# IMPORTANT: tmux RENUMBERS pane indices on each split — they follow layout-
# tree DFS order (top-down, left-right), NOT creation order. So don't set
# titles between splits; do all splits first, then label by final index.
#
# Step 1: split pane 0 horizontally — left column / right column.
tmux split-window -h -t "${SESSION_NAME}:team.0" -p 50 -c "${USER_PWD}"
# Step 2: subdivide the right column into 3 stacked panes.
tmux split-window -v -t "${SESSION_NAME}:team.1" -p 67 -c "${USER_PWD}"
tmux split-window -v -t "${SESSION_NAME}:team.2" -p 50 -c "${USER_PWD}"
# Step 3: split the left column vertically (main 60% / worker-review 40%).
# After this split, tmux re-indexes: the new bottom-left pane becomes index 1,
# right-column panes shift to 2/3/4.
tmux split-window -v -t "${SESSION_NAME}:team.0" -p 40 -c "${USER_PWD}"

# Final layout (after tmux renumbering):
#   team.0 = main           (top-left, 50% wide × 60% tall)
#   team.1 = worker-review  (bottom-left, 50% wide × 40% tall)
#   team.2 = worker-fe      (top-right, 50% wide × ~33% tall)
#   team.3 = worker-be      (mid-right, 50% wide × ~33% tall)
#   team.4 = worker-qa      (bottom-right, 50% wide × ~33% tall)

# Now set titles based on the final indices.
tmux select-pane -t "${SESSION_NAME}:team.0" -T "main (Technoking)"
tmux select-pane -t "${SESSION_NAME}:team.1" -T "worker-review (Roastmaster)"
tmux select-pane -t "${SESSION_NAME}:team.2" -T "worker-fe (Pixel Wizard)"
tmux select-pane -t "${SESSION_NAME}:team.3" -T "worker-be (Persistence Paladin)"
tmux select-pane -t "${SESSION_NAME}:team.4" -T "worker-qa (What-If Witch)"

# --- Launch claude in every pane (main = interactive, workers = silent polling) ---
# Bash 3 compatible — no associative arrays.
for pane_idx in 0 1 2 3 4; do
  case "$pane_idx" in
    0) persona="technoking";          pane_name="main"          ;;
    1) persona="the-roastmaster";     pane_name="worker-review" ;;
    2) persona="pixel-wizard";        pane_name="worker-fe"     ;;
    3) persona="persistence-paladin"; pane_name="worker-be"     ;;
    4) persona="what-if-witch";       pane_name="worker-qa"     ;;
  esac
  tmux_target="${SESSION_NAME}:team.${pane_idx}"
  "${LAUNCH_SCRIPT}" "${tmux_target}" "${persona}" "${pane_name}" || {
    echo "ERROR: worker-launch.sh failed for pane ${pane_idx} (${persona})" >&2
    exit 1
  }
done

# --- Focus main pane for user ---
tmux select-pane -t "${SESSION_NAME}:team.0"

# --- Report ---
cat <<EOF
[tmux-setup] Session '${SESSION_NAME}' ready (cwd: ${USER_PWD}).

Pane layout:
  team.0  main           — Technoking (interactive, user-facing)
  team.1  worker-review  — The Roastmaster
  team.2  worker-fe      — Pixel Wizard
  team.3  worker-be      — Persistence Paladin
  team.4  worker-qa      — What-If Witch

Attach with:
  tmux attach -t ${SESSION_NAME}
EOF
