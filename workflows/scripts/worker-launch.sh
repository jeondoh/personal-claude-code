#!/usr/bin/env bash
# worker-launch.sh — launch a headless claude instance in a tmux pane with a persona attached
# Usage: worker-launch.sh <pane-id> <persona-slug> [--initial-task <ticket-id>]
# Exit codes: 0=ok 1=generic 2=preflight 3=lock 4=bad-args
set -euo pipefail
IFS=$'\n\t'

CLAUDE_TEAM_DIR="${CLAUDE_TEAM_DIR:-.claude-team}"
AGENTS_DIR="workflows/agents"
REGISTRY="${CLAUDE_TEAM_DIR}/workers/registry.json"

# ---------- helpers ----------------------------------------------------------

die()      { echo "ERROR: $*" >&2; exit 1; }
die_pre()  { echo "PREFLIGHT: $*" >&2; exit 2; }
die_args() { echo "ARGS: $*" >&2; exit 4; }

# Acquire advisory counter lock; retry up to 30 times with 100ms sleep.
acquire_lock() {
  local lock="${CLAUDE_TEAM_DIR}/.counter.lock"
  local i=0
  while ! mkdir "$lock" 2>/dev/null; do
    i=$(( i + 1 ))
    [[ $i -ge 30 ]] && { echo "ERROR: lock timeout" >&2; exit 3; }
    sleep 0.1
  done
}
release_lock() { rmdir "${CLAUDE_TEAM_DIR}/.counter.lock" 2>/dev/null || true; }

# Strip YAML frontmatter (between first pair of ---) from stdin.
strip_frontmatter() {
  awk '/^---/{if(f==0){f=1;next}else{f=2;next}} f==2{print}' "$1"
}

# Read a frontmatter field from a markdown file.
# Usage: fm_field <file> <key>
fm_field() {
  grep -m1 "^${2}:" "$1" | cut -d':' -f2- | sed 's/^ *//' | tr -d "'\""
}

# Update registry panes using jq (preferred) or python3 fallback.
update_registry_panes() {
  local slug="$1" pane_id="$2" pid="$3"
  local tmp="${REGISTRY}.$$"
  if command -v jq &>/dev/null; then
    jq --arg slug "$slug" --arg pane "$pane_id" --arg pid "$pid" \
      '.panes[$slug] = {pane_id: $pane, pid: ($pid | tonumber)}' \
      "$REGISTRY" > "$tmp"
  elif command -v python3 &>/dev/null; then
    python3 - "$REGISTRY" "$tmp" "$slug" "$pane_id" "$pid" <<'PYEOF'
import sys, json
src, dst, slug, pane_id, pid = sys.argv[1:]
data = json.load(open(src))
data.setdefault("panes", {})[slug] = {"pane_id": pane_id, "pid": int(pid)}
json.dump(data, open(dst, "w"), indent=2)
PYEOF
  else
    die "neither jq nor python3 found — cannot update registry"
  fi
  mv -f "$tmp" "$REGISTRY"
}

# ---------- arg parse --------------------------------------------------------

[[ $# -lt 2 ]] && die_args "Usage: worker-launch.sh <pane-id> <persona-slug> [--initial-task <ticket-id>]"

PANE_ID="$1"
SLUG="$2"
INITIAL_TASK=""
shift 2

while [[ $# -gt 0 ]]; do
  case "$1" in
    --initial-task) INITIAL_TASK="${2:-}"; shift 2 ;;
    *) die_args "Unknown arg: $1" ;;
  esac
done

# Validate pane-id format (e.g. 6:0.0 or worker-be)
[[ "$PANE_ID" =~ ^[a-zA-Z0-9:._-]+$ ]] || die_args "Invalid pane-id: $PANE_ID"

PERSONA_FILE="${AGENTS_DIR}/${SLUG}.md"
[[ -f "$PERSONA_FILE" ]] || die_pre "Persona file not found: $PERSONA_FILE"
[[ -f "$REGISTRY" ]]     || die_pre "registry.json not found — run /setup-team first"

# ---------- preflight --------------------------------------------------------

command -v tmux &>/dev/null || die_pre "tmux not found in PATH"
tmux has-session 2>/dev/null       || die_pre "no tmux session active"
tmux select-pane -t "$PANE_ID" &>/dev/null \
  || die_pre "tmux pane not found: $PANE_ID"

# ---------- build persona prompt ---------------------------------------------

MODEL="$(fm_field "$PERSONA_FILE" model)"
[[ -z "$MODEL" ]] && MODEL="sonnet"   # safe default

PERSONA_BODY="$(strip_frontmatter "$PERSONA_FILE")"
SYSTEM_PROMPT="${PERSONA_BODY}

You are ${SLUG}. Before acting: read CLAUDE.md, your persona file (${PERSONA_FILE}), and your assigned skills."

read -r -d '' DEFAULT_BOOTSTRAP <<EOF || true
You are now in idle polling mode for ${SLUG}. Follow tmux-worker-protocol § Polling cycle.

Polling protocol (REPEAT until a ticket appears — do not stop after one poll):

Step 1. Execute this Bash block (use the Bash tool, timeout 320000ms):

  for i in \$(seq 1 10); do
    out=\$(workflows/scripts/ticket-poll.sh ${SLUG} 2>&1)
    echo "[poll \$i @ \$(TZ=Asia/Seoul date +%H:%M:%S)] \$out"
    case "\$out" in
      none:*) sleep 30 ;;
      *) break ;;
    esac
  done

Step 2. Inspect the final output:
  - If a non-"none:" line appeared → run \`workflows/scripts/ticket-poll.sh ${SLUG} --claim\` to atomically move the ticket to in-progress/, read it from .claude-team/tickets/in-progress/, then begin work per ticket-protocol.
  - If ALL 10 polls returned "none:" → repeat Step 1 (run the Bash block again). Continue indefinitely.

Constraints while idle:
- Do NOT run slash commands (none defined for headless workers).
- Do NOT explore the codebase, edit files, or call tools other than Bash polling.
- Do NOT exit the polling loop. Only break out when a real ticket appears.
EOF

BOOTSTRAP_TASK="${INITIAL_TASK:-$DEFAULT_BOOTSTRAP}"

# ---------- launch -----------------------------------------------------------

# VERIFY: confirm flags against \`claude --help\` in stage 9 smoke test.
# Assumed signature based on Claude Code conventions:
#   claude --print --append-system-prompt "<persona-body>" "<first-task>"
# If flags differ, /setup-team's preflight will surface the exact error.
# NOTE: model flag assumed --model <model>. Adjust if CLI differs.

LAUNCH_CMD="claude --model ${MODEL} --append-system-prompt $(printf '%q' "$SYSTEM_PROMPT") $(printf '%q' "$BOOTSTRAP_TASK")"

tmux send-keys -t "$PANE_ID" "$LAUNCH_CMD" Enter

# Give the process a moment to start, then capture its PID via tmux pane_pid.
sleep 0.5
PANE_PID="$(tmux display-message -t "$PANE_ID" -p '#{pane_pid}' 2>/dev/null)" \
  || die "Could not read pane PID for $PANE_ID"

# ---------- update registry --------------------------------------------------

acquire_lock
update_registry_panes "$SLUG" "$PANE_ID" "$PANE_PID"
release_lock

echo "launched: ${SLUG} pane=${PANE_ID} pid=${PANE_PID}"
