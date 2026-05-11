#!/usr/bin/env bash
# ticket-poll.sh — poll the ticket queue for a persona; optionally claim tickets
# Usage: ticket-poll.sh <persona-slug> [--claim] [--max <N>]
#   Without --claim: list matching tickets (read-only).
#   With    --claim: atomically move up to N tickets to in-progress.
# Exit codes: 0=ok 1=generic 2=preflight 4=bad-args
set -euo pipefail
IFS=$'\n\t'

CLAUDE_TEAM_DIR="${CLAUDE_TEAM_DIR:-.claude-team}"
# Self-locate: script lives in <plugin-root>/bin/, persona files in <plugin-root>/agents/.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
AGENTS_DIR="${PLUGIN_ROOT}/agents"
QUEUE_DIR="${CLAUDE_TEAM_DIR}/tickets/queue"
INPROG_DIR="${CLAUDE_TEAM_DIR}/tickets/in-progress"

die()      { echo "ERROR: $*" >&2; exit 1; }
die_pre()  { echo "PREFLIGHT: $*" >&2; exit 2; }
die_args() { echo "ARGS: $*" >&2; exit 4; }

kst_now() { TZ=Asia/Seoul date +'%Y-%m-%dT%H:%M:%S+09:00'; }

# Read a YAML frontmatter field; prints empty string if absent.
fm_field() { grep -m1 "^${2}:" "$1" 2>/dev/null | cut -d':' -f2- | sed "s/^ *//;s/['\"]//g" || true; }

# In-place sed update for a frontmatter key (only the claiming worker writes its
# own in-progress ticket, so no concurrent writes on the same file).
fm_set() {
  local f="$1" key="$2" val="$3" tmp="${1}.$$"
  if grep -qm1 "^${key}:" "$f"; then
    sed "s|^${key}:.*|${key}: ${val}|" "$f" > "$tmp"
  else
    awk -v k="$key" -v v="$val" 'NR==1&&/^---/{print;print k": "v;next}{print}' "$f" > "$tmp"
  fi
  mv -f "$tmp" "$f"
}

# ---------- args -------------------------------------------------------------

[[ $# -lt 1 ]] && die_args "Usage: ticket-poll.sh <persona-slug> [--claim] [--max <N>]"
SLUG="$1"; CLAIM=false; MAX=1; shift

while [[ $# -gt 0 ]]; do
  case "$1" in
    --claim) CLAIM=true; shift ;;
    --max)
      [[ "${2:-}" =~ ^[1-9][0-9]*$ ]] || die_args "--max requires a positive integer"
      MAX="$2"; shift 2 ;;
    *) die_args "Unknown arg: $1" ;;
  esac
done

# ---------- preflight --------------------------------------------------------

[[ -f "${AGENTS_DIR}/${SLUG}.md" ]] || die_pre "Persona not found: ${AGENTS_DIR}/${SLUG}.md"
[[ -d "$QUEUE_DIR" ]]   || die_pre "Queue dir not found — run /setup-team first"
[[ -d "$INPROG_DIR" ]]  || die_pre "In-progress dir not found — run /setup-team first"

# ---------- collect + sort candidates ----------------------------------------

shopt -s nullglob
ALL=( "${QUEUE_DIR}"/T-*.md "${QUEUE_DIR}"/RV-*.md )
shopt -u nullglob

if [[ ${#ALL[@]} -eq 0 ]]; then
  echo "none: queue is empty"; exit 0
fi

# Build <created-ts>\t<filepath>, sort oldest-first, extract paths.
mapfile -t SORTED < <(
  for f in "${ALL[@]}"; do
    ASSIGNEE="$(fm_field "$f" assignee)"
    [[ "$ASSIGNEE" == "$SLUG" || "$ASSIGNEE" == "unassigned" || -z "$ASSIGNEE" ]] || continue
    CREATED="$(fm_field "$f" created)"
    printf '%s\t%s\n' "${CREATED:-0000}" "$f"
  done | sort -k1,1 | cut -f2-
)

if [[ ${#SORTED[@]} -eq 0 ]]; then
  echo "none: no tickets for ${SLUG} in queue"; exit 0
fi

# ---------- list (no --claim) ------------------------------------------------

if ! $CLAIM; then
  echo "queue for ${SLUG} (${#SORTED[@]} ticket(s)):"
  for f in "${SORTED[@]}"; do
    ID="$(fm_field "$f" "id")"
    TITLE="$(fm_field "$f" title)"
    CMPLX="$(fm_field "$f" complexity)"
    printf '  %-12s  %-40s  %s\n' "${ID:-$(basename "$f")}" "${TITLE:-(no title)}" "${CMPLX:-}"
  done
  exit 0
fi

# ---------- claim ------------------------------------------------------------

CLAIMED=0
NOW="$(kst_now)"

for f in "${SORTED[@]}"; do
  [[ $CLAIMED -ge $MAX ]] && break
  FNAME="$(basename "$f")"
  DEST="${INPROG_DIR}/${FNAME}"
  # Atomic mv — fails silently if another pane already claimed this ticket.
  if mv "$f" "$DEST" 2>/dev/null; then
    fm_set "$DEST" status     "in_progress"
    fm_set "$DEST" owner      "$SLUG"
    fm_set "$DEST" claimed_at "$NOW"
    ID="$(fm_field "$DEST" "id")"
    echo "claimed: ${ID:-$FNAME} path=${DEST}"
    CLAIMED=$(( CLAIMED + 1 ))
  fi
done

[[ $CLAIMED -eq 0 ]] && echo "none: all candidates already claimed by another pane"
exit 0
