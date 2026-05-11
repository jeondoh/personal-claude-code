#!/usr/bin/env bash
# worker-launch.sh — launch a claude instance in a tmux pane with a persona attached.
# Two modes:
#   - main pane (pane-name=main, persona=technoking): interactive Tech Lead with a
#     short welcome; not tracked in registry; no polling loop.
#   - worker pane (worker-be/fe/qa/review): silent polling loop with a one-time
#     persona-specific greeting from the persona's `idle_greeting:` frontmatter.
#
# Usage: worker-launch.sh <pane-id> <persona-slug> <pane-name> [--initial-task <text>]
#   pane-id     tmux target (e.g. "claude-team:team.2")
#   persona-slug agents/<slug>.md filename without .md (e.g. "persistence-paladin")
#   pane-name   stable identifier — "main" or "worker-*"
# Exit codes: 0=ok 1=generic 2=preflight 3=lock 4=bad-args
set -euo pipefail
IFS=$'\n\t'

CLAUDE_TEAM_DIR="${CLAUDE_TEAM_DIR:-.claude-team}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
AGENTS_DIR="${PLUGIN_ROOT}/agents"
REGISTRY="${CLAUDE_TEAM_DIR}/workers/registry.json"

# ---------- helpers ----------------------------------------------------------

die()      { echo "ERROR: $*" >&2; exit 1; }
die_pre()  { echo "PREFLIGHT: $*" >&2; exit 2; }
die_args() { echo "ARGS: $*" >&2; exit 4; }

acquire_lock() {
  local lock="${CLAUDE_TEAM_DIR}/.counter.lock" i=0
  while ! mkdir "$lock" 2>/dev/null; do
    i=$(( i + 1 ))
    [[ $i -ge 30 ]] && { echo "ERROR: lock timeout" >&2; exit 3; }
    sleep 0.1
  done
}
release_lock() { rmdir "${CLAUDE_TEAM_DIR}/.counter.lock" 2>/dev/null || true; }

strip_frontmatter() {
  awk '/^---/{if(f==0){f=1;next}else{f=2;next}} f==2{print}' "$1"
}

# Read a frontmatter field; strips surrounding quotes. Empty if absent.
fm_field() {
  grep -m1 "^${2}:" "$1" 2>/dev/null | cut -d':' -f2- | sed 's/^ *//' | sed 's/^"//;s/"$//' | sed "s/^'//;s/'\$//"
}

# Resolve to absolute path. Pane shell may have a different cwd than this script.
to_abs() {
  case "$1" in
    /*) printf '%s' "$1" ;;
     *) printf '%s/%s' "$(pwd)" "$1" ;;
  esac
}

update_registry_panes() {
  local pane_name="$1" persona="$2" pane_id="$3" pid="$4"
  local tmp="${REGISTRY}.$$"
  if command -v jq &>/dev/null; then
    jq --arg name "$pane_name" --arg persona "$persona" --arg pane_id "$pane_id" --arg pid "$pid" \
      '.panes[$name] = {persona: $persona, pid: ($pid | tonumber), pane_id: $pane_id}' \
      "$REGISTRY" > "$tmp"
  elif command -v python3 &>/dev/null; then
    python3 - "$REGISTRY" "$tmp" "$pane_name" "$persona" "$pane_id" "$pid" <<'PYEOF'
import sys, json
src, dst, name, persona, pane_id, pid = sys.argv[1:]
data = json.load(open(src))
data.setdefault("panes", {})[name] = {"persona": persona, "pid": int(pid), "pane_id": pane_id}
json.dump(data, open(dst, "w"), indent=2)
PYEOF
  else
    die "neither jq nor python3 found — cannot update registry"
  fi
  mv -f "$tmp" "$REGISTRY"
}

# ---------- arg parse --------------------------------------------------------

[[ $# -lt 3 ]] && die_args "Usage: worker-launch.sh <pane-id> <persona-slug> <pane-name> [--initial-task <text>]"

PANE_ID="$1"
SLUG="$2"
PANE_NAME="$3"
INITIAL_TASK=""
shift 3

while [[ $# -gt 0 ]]; do
  case "$1" in
    --initial-task) INITIAL_TASK="${2:-}"; shift 2 ;;
    *) die_args "Unknown arg: $1" ;;
  esac
done

[[ "$PANE_ID" =~ ^[a-zA-Z0-9:._-]+$ ]] || die_args "Invalid pane-id: $PANE_ID"
[[ "$PANE_NAME" =~ ^[a-z0-9][a-z0-9-]{0,39}$ ]] || die_args "Invalid pane-name: $PANE_NAME"

PERSONA_FILE="${AGENTS_DIR}/${SLUG}.md"
[[ -f "$PERSONA_FILE" ]] || die_pre "Persona file not found: $PERSONA_FILE"
[[ -f "$REGISTRY" ]]     || die_pre "registry.json not found — run /setup-team first"

# ---------- preflight --------------------------------------------------------

command -v tmux &>/dev/null || die_pre "tmux not found in PATH"
tmux has-session 2>/dev/null || die_pre "no tmux session active"
tmux select-pane -t "$PANE_ID" &>/dev/null || die_pre "tmux pane not found: $PANE_ID"

# ---------- assemble system prompt -------------------------------------------

MODEL="$(fm_field "$PERSONA_FILE" model)"
[[ -z "$MODEL" ]] && MODEL="sonnet"

PERSONA_BODY="$(strip_frontmatter "$PERSONA_FILE")"
SYSTEM_PROMPT="${PERSONA_BODY}

You are ${SLUG}. Before acting: read CLAUDE.md, your persona file (${PERSONA_FILE}), and your assigned skills."

# ---------- persist persona prompt to file -----------------------------------
# Both main and worker panes need the persona body in a file so claude can
# pick it up via --append-system-prompt-file. Done before mode branching.

RUNTIME_DIR="${CLAUDE_TEAM_DIR}/.runtime"
mkdir -p "$RUNTIME_DIR"
PROMPT_FILE="${RUNTIME_DIR}/${SLUG}.prompt"
printf '%s' "$SYSTEM_PROMPT" > "$PROMPT_FILE"
ABS_PROMPT_FILE="$(to_abs "$PROMPT_FILE")"

# ---------- launch (mode-specific) -------------------------------------------
# main pane     → claude with welcome message (interactive, user-facing)
# worker panes  → worker-idle.sh shell loop (no claude until a ticket arrives)
#
# Why split: worker-idle.sh keeps the pane chat log clean during idle (just a
# few short log lines, no Bash tool UI). When a ticket is claimed, the shell
# execs claude with the ticket as first message; when claude finishes (it
# touches a sentinel file), shell resumes polling.

if [[ "$PANE_NAME" == "main" ]]; then
  read -r -d '' WELCOME <<EOF || true
이 메시지는 사용자에게 출력하는 환영 인사다. 정확히 한 번 다음 텍스트만 출력하고 사용자 입력을 기다린다. 추가 설명·다른 동작 없음.

━━ Technoking 작업대 ━━
워커 4명 (worker-review · worker-fe · worker-be · worker-qa) 백그라운드 폴링 중.

자주 쓰는 명령:
  /feat <요청>   — 전체 라이프사이클 (PRD → 설계 → 구현 → 리뷰 → 머지)
  /task <요청>   — 작은 작업 (1-2 파일, 단일 영역)
  /design <요청> — PRD · 설계 문서만
  /status        — 워커 진행 보드
  /show-team     — 팀 로스터 + PID
  /abort <T-NNNN>— 진행 중 ticket 중단

여기서 명령 주면 워커들에게 분배된다. 다른 페인은 들여다보지 말고 이 작업대에서 명령만.
━━━━━━━━━━━━━━━━━━━━━━━━━━━

위 텍스트를 출력한 직후 무조건 사용자 입력 대기. 자동 동작·자동 polling X.
EOF

  TASK_FILE="${RUNTIME_DIR}/${SLUG}.task"
  printf '%s' "${INITIAL_TASK:-$WELCOME}" > "$TASK_FILE"
  ABS_TASK_FILE="$(to_abs "$TASK_FILE")"

  LAUNCH_CMD="claude --dangerously-skip-permissions --model ${MODEL} --append-system-prompt-file $(printf '%q' "$ABS_PROMPT_FILE") \"\$(cat $(printf '%q' "$ABS_TASK_FILE"))\""
else
  # Worker pane: start the pure-shell polling loop. worker-idle.sh resolves
  # via PATH (plugin's bin/ is on PATH).
  LAUNCH_CMD="worker-idle.sh $(printf '%q' "$SLUG") $(printf '%q' "$PANE_NAME") $(printf '%q' "$ABS_PROMPT_FILE")"
fi

tmux send-keys -t "$PANE_ID" "$LAUNCH_CMD" Enter

sleep 0.5
PANE_PID="$(tmux display-message -t "$PANE_ID" -p '#{pane_pid}' 2>/dev/null)" \
  || die "Could not read pane PID for $PANE_ID"

# ---------- update registry (workers only; main is implicit) -----------------

if [[ "$PANE_NAME" != "main" ]]; then
  acquire_lock
  update_registry_panes "$PANE_NAME" "$SLUG" "$PANE_ID" "$PANE_PID"
  release_lock
fi

echo "launched: ${SLUG} pane=${PANE_NAME} target=${PANE_ID} pid=${PANE_PID}"
