#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Launch the claude-team tmux session with 5 panes matching the BUILD-PROGRESS layout.
# Called by /setup-team after config.yml is written.
#
# Usage: tmux-setup.sh [--session-name <name>]
#   Default session name: claude-team
#
# Exit codes: 0=ok, 1=generic fail, 2=preflight fail

CLAUDE_TEAM_DIR="${CLAUDE_TEAM_DIR:-.claude-team}"
SESSION_NAME="claude-team"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAUNCH_SCRIPT="${SCRIPT_DIR}/worker-launch.sh"

# --- Parse args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --session-name)
      SESSION_NAME="$2"
      shift 2
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 1
      ;;
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
  # Non-fatal: proceed; worker-launch.sh will need it later.
fi

if [[ ! -x "${LAUNCH_SCRIPT}" ]]; then
  echo "ERROR: worker-launch.sh not found or not executable at ${LAUNCH_SCRIPT}" >&2
  exit 2
fi

# --- Idempotent session guard ---
if tmux has-session -t "${SESSION_NAME}" 2>/dev/null; then
  echo "Session '${SESSION_NAME}' already exists. Attaching..."
  tmux attach-session -t "${SESSION_NAME}"
  exit 0
fi

# --- Create session (main pane, left half) ---
# Initial window named 'team'; first pane = main (Technoking, user-facing).
tmux new-session -d -s "${SESSION_NAME}" -n team
tmux select-pane -t "${SESSION_NAME}:team.0" -T "main (Technoking)"

# --- Build layout: left 50% | right 50% split into 3 ---
# Split vertically → left=pane 0 (main), right=pane 1 (worker-fe top)
tmux split-window -h -t "${SESSION_NAME}:team.0" -p 50
tmux select-pane -t "${SESSION_NAME}:team.1" -T "worker-fe (Pixel Wizard)"

# Split right pane horizontally → worker-fe (top) + worker-be (middle-temp)
tmux split-window -v -t "${SESSION_NAME}:team.1" -p 67
tmux select-pane -t "${SESSION_NAME}:team.2" -T "worker-be (Persistence Paladin)"

# Split worker-be pane → worker-be (top) + worker-qa (bottom)
tmux split-window -v -t "${SESSION_NAME}:team.2" -p 50
tmux select-pane -t "${SESSION_NAME}:team.3" -T "worker-qa (What-If Witch)"

# Split left pane (main) horizontally → main (top) + worker-review (bottom)
tmux split-window -v -t "${SESSION_NAME}:team.0" -p 40
tmux select-pane -t "${SESSION_NAME}:team.4" -T "worker-review (The Roastmaster)"

# --- Launch headless workers (right-side panes + worker-review) ---
# Pane indices after splits: 0=main, 1=worker-fe, 2=worker-be, 3=worker-qa, 4=worker-review
# main (pane 0) is left for the user; no headless claude there.

# Bash 3-compatible (macOS ships bash 3.2; no associative arrays via `declare -A`).
for pane_idx in 1 2 3 4; do
  case "$pane_idx" in
    1) persona="pixel-wizard" ;;
    2) persona="persistence-paladin" ;;
    3) persona="what-if-witch" ;;
    4) persona="the-roastmaster" ;;
  esac
  tmux_target="${SESSION_NAME}:team.${pane_idx}"
  "${LAUNCH_SCRIPT}" "${tmux_target}" "${persona}" || {
    echo "ERROR: worker-launch.sh failed for pane ${pane_idx} (${persona})" >&2
    exit 1
  }
done

# --- Focus main pane for user ---
tmux select-pane -t "${SESSION_NAME}:team.0"

# --- Report ---
cat <<EOF
[tmux-setup] Session '${SESSION_NAME}' ready.

Pane layout:
  team.0  main          — Technoking (user-facing, no headless worker)
  team.4  worker-review — The Roastmaster
  team.1  worker-fe     — Pixel Wizard
  team.2  worker-be     — Persistence Paladin
  team.3  worker-qa     — What-If Witch

Attach with:
  tmux attach -t ${SESSION_NAME}
EOF
