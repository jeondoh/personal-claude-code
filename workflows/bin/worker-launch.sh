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
  read -r -d '' WELCOME <<'EOF' || true
새 세션 첫 호출이다. 페르소나 정의의 §Initial Run Routine 을 지금 정확히 한 번 실행하고 보고한다. 같은 세션 내 반복 발동 X.

순서 (read-only · 새 ticket 발행·dispatch 금지):
1. `.claude-team/config.yml` + `.claude-team/workers/registry.json` 존재 확인 — 없으면 "`/setup-team` 부터 실행해주세요." 한 줄 안내 후 중단
2. `.claude-team/workers/registry.json` — 페인·페르소나·PID 상태
3. `.claude-team/tickets/in-progress/`, `.claude-team/tickets/queue/` — 진행·대기 ticket 수와 ID
4. `.claude-team/inbox/` — 미처리 알림 (`error_2x`, `pattern_stuck`, `fix_pushed`, `escalation_needed`)
5. `.claude-team/rescues/` — in-flight rescue 여부
6. `.claude-team/handoff/` — 최신 `HANDOFF-*.md` 본문 핵심 1~2줄
7. `git status` + 현재 브랜치 — 미커밋·머지 대기 PR 여부

보고 (한국어 존대, 짧게):
- 헤더: `━━ Technoking 작업대 ━━`
- 상태 1줄: `진행 N / 대기 N / 알림 N / rescue M`
- 즉시 처리 항목 (있을 때만): 미처리 inbox 알림 · `escalation_needed` ticket · 머지 대기 PR
- 다음 진행거리 1~3개 (우선순위 순) — "다음 액션이 무엇인지" 명확하게
- 액션 제안: 자동 진행 가능 건은 진행 여부 확인, 사용자 결정 필요 건은 옵션 제시
- HANDOFF 발견 시: 본문 핵심 1~2줄 + `/handoff --resume` 제안
- Empty state (모두 비어있음): "팀 준비 완료, 진행 중 없음. /feat | /task | /design 중 선택해주세요."

보고 말미에 자주 쓰는 명령 한 줄로 첨부:
  /feat <요청> · /task <요청> · /design <요청> · /status · /show-team · /abort <T-NNNN>

보고 출력 직후 사용자 입력 대기. 자동 dispatch X.
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
