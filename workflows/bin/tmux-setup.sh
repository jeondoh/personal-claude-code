#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Launch the claude-team tmux session: 5 panes (main + 4 workers), all rooted
# at the user's current working directory. main pane runs Technoking
# interactively; worker panes run silent polling claude instances.
#
# Pane index → name mapping (visual reading order, top-down):
#   team.0  main           (top-left)            Technoking
#   team.1  worker-review  (bottom-left)         The Roastmaster
#   team.2  worker-fe      (top-right)           Pixel Wizard
#   team.3  worker-be      (middle-right)        Persistence Paladin
#   team.4  worker-qa      (bottom-right)        What-If Witch
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
  echo "WARNING: ${CLAUDE_TEAM_DIR}/config.yml not found. /setup-team should have created it." >&2
fi
if [[ ! -x "${LAUNCH_SCRIPT}" ]]; then
  echo "ERROR: worker-launch.sh not found or not executable at ${LAUNCH_SCRIPT}" >&2
  exit 2
fi

# --- Idempotent session guard ---
# When called from inside an existing tmux session, attaching nested fails.
# Print attach hint and exit success.
if tmux has-session -t "${SESSION_NAME}" 2>/dev/null; then
  echo "Session '${SESSION_NAME}' already exists — leaving panes intact."
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

# --- Build layout (split order chosen so pane indices match visual order) ---
# Order matters: tmux assigns the next available index to each new pane.
# Proportions: top row 70% / bottom 30%; top split 50/50 horizontal; right
# column split into thirds.
#
# Step 1: split pane 0 vertically — new pane 1 takes the bottom 30%
#         (Roastmaster). Pane 0 retains the top 70%.
tmux split-window -v -t "${SESSION_NAME}:team.0" -p 30 -c "${USER_PWD}"
tmux select-pane -t "${SESSION_NAME}:team.1" -T "worker-review (Roastmaster)"

# Step 2: split pane 0 (top) horizontally — new pane 2 is top-right 50%.
tmux split-window -h -t "${SESSION_NAME}:team.0" -p 50 -c "${USER_PWD}"
tmux select-pane -t "${SESSION_NAME}:team.2" -T "worker-fe (Pixel Wizard)"

# Step 3: split pane 2 (top-right) vertically — new pane 3 is the lower 2/3.
tmux split-window -v -t "${SESSION_NAME}:team.2" -p 67 -c "${USER_PWD}"
tmux select-pane -t "${SESSION_NAME}:team.3" -T "worker-be (Persistence Paladin)"

# Step 4: split pane 3 (lower-right) vertically — new pane 4 is the bottom 50%.
tmux split-window -v -t "${SESSION_NAME}:team.3" -p 50 -c "${USER_PWD}"
tmux select-pane -t "${SESSION_NAME}:team.4" -T "worker-qa (What-If Witch)"

# Final layout:
#   team.0 = main          (top-left, 50% wide × 70% tall)
#   team.1 = worker-review (bottom row, full width × 30% tall)
#   team.2 = worker-fe     (top-right, 50% wide × ~23% tall)
#   team.3 = worker-be     (mid-right, 50% wide × ~23% tall)
#   team.4 = worker-qa     (bottom-right, 50% wide × ~23% tall)

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
