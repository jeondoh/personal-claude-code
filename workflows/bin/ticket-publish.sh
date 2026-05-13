#!/usr/bin/env bash
# ticket-publish.sh — atomically publish a ticket to the queue and increment the counter
# Usage: ticket-publish.sh <type> <slug> <body-file>
#   type  ∈ work|review|backlog
#   slug  kebab-case label for filename (lowercase+hyphens, ≤40 chars)
# Exit codes: 0=ok 1=generic 2=preflight 3=lock 4=bad-args
set -euo pipefail
IFS=$'\n\t'

CLAUDE_TEAM_DIR="${CLAUDE_TEAM_DIR:-.claude-team}"
REGISTRY="${CLAUDE_TEAM_DIR}/workers/registry.json"
QUEUE_DIR="${CLAUDE_TEAM_DIR}/tickets/queue"

die()      { echo "ERROR: $*" >&2; exit 1; }
die_pre()  { echo "PREFLIGHT: $*" >&2; exit 2; }
die_args() { echo "ARGS: $*" >&2; exit 4; }

acquire_lock() {
  local lock="${CLAUDE_TEAM_DIR}/.counter.lock" i=0
  while ! mkdir "$lock" 2>/dev/null; do
    (( i++ )); [[ $i -ge 30 ]] && { echo "ERROR: lock timeout" >&2; exit 3; }
    sleep 0.1
  done
}
release_lock() { rmdir "${CLAUDE_TEAM_DIR}/.counter.lock" 2>/dev/null || true; }

kst_now() { TZ=Asia/Seoul date +'%Y-%m-%dT%H:%M:%S+09:00'; }

# Increment a counter key in registry.json and write atomically to <out>.
registry_bump() {  # registry_bump <key> <new-val> <out-file>
  if command -v jq &>/dev/null; then
    jq --arg k "$1" --argjson v "$2" '.counters[$k] = $v' "$REGISTRY" > "$3"
  else
    python3 - "$REGISTRY" "$1" "$2" "$3" <<'EOF'
import sys, json
src, key, val, dst = sys.argv[1:]
d = json.load(open(src)); d["counters"][key] = int(val)
json.dump(d, open(dst, "w"), indent=2)
EOF
  fi
}

counter_get() {  # counter_get <key>  → prints integer
  if command -v jq &>/dev/null; then
    jq -r ".counters.${1}" "$REGISTRY"
  else
    python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d['counters']['${1}'])" "$REGISTRY"
  fi
}

fm_has() { grep -qm1 "^${2}:" "$1"; }  # fm_has <file> <key>

# ---------- args -------------------------------------------------------------

[[ $# -ne 3 ]] && die_args "Usage: ticket-publish.sh <type> <slug> <body-file>"
TYPE="$1"; SLUG="$2"; BODY_FILE="$3"

case "$TYPE" in
  work)    KEY="T";  PREFIX="T"  ;;
  review)  KEY="RV"; PREFIX="RV" ;;
  backlog) KEY="BL"; PREFIX="BL" ;;
  *) die_args "type must be one of: work review backlog" ;;
esac

[[ "$SLUG" =~ ^[a-z0-9][a-z0-9-]{0,39}$ ]] \
  || die_args "slug must be lowercase-hyphen ≤40 chars"
[[ -f "$BODY_FILE" ]] || die_args "body-file not found: $BODY_FILE"

# ---------- preflight --------------------------------------------------------

[[ -f "$REGISTRY" ]]  || die_pre "registry.json not found — run /setup-team first"
[[ -d "$QUEUE_DIR" ]] || die_pre "queue dir not found: $QUEUE_DIR"

# counters 무결성 검증
if command -v jq &>/dev/null; then
  jq -e '.counters.T and .counters.RV and .counters.BL | (type=="number" or .)' "$REGISTRY" &>/dev/null \
    || die_pre "registry.json counters 손상 — {T,RV,BL} 키 없음"
fi

# ---------- lock + ID --------------------------------------------------------

acquire_lock
CURRENT="$(counter_get "$KEY")"
[[ "$CURRENT" =~ ^[0-9]+$ ]] || die "counter $KEY is not a number"
NEXT=$(( CURRENT + 1 ))
PADDED="$(printf '%04d' "$NEXT")"  # expands beyond 4 digits naturally for N≥10000
TICKET_ID="${PREFIX}-${PADDED}"
FILENAME="${TICKET_ID}-${SLUG}.md"
DEST="${QUEUE_DIR}/${FILENAME}"
[[ -f "$DEST" ]] && die "destination already exists (counter sync issue?): $DEST"

# ---------- validate / auto-patch frontmatter --------------------------------

TMP="/tmp/$$.${TICKET_ID}.md"
cp "$BODY_FILE" "$TMP"

HAS_FM=false
[[ "$(head -n1 "$TMP")" == "---" ]] && HAS_FM=true

if $HAS_FM; then
  # 누락된 필드만 frontmatter 안에 삽입
  TMP2="${TMP}.p"
  TITLE_DEFAULT="$(grep -m1 '^# ' "$TMP" | sed 's/^# //' || echo "$SLUG")"
  awk -v tp="$TYPE" -v id="$TICKET_ID" -v ttl="$TITLE_DEFAULT" -v ts="$(kst_now)" '
    BEGIN { in_fm=0; emitted_open=0; have_type=0; have_id=0; have_title=0; have_status=0; have_created=0; have_author=0 }
    /^---/ {
      if (!emitted_open) { print; in_fm=1; emitted_open=1; next }
      else if (in_fm) {
        if (!have_type)    print "type: " tp
        if (!have_id)      print "id: " id
        if (!have_title)   print "title: " ttl
        if (!have_status)  print "status: queued"
        if (!have_author)  print "author: technoking"
        if (!have_created) print "created: " ts
        print; in_fm=0; next
      }
    }
    in_fm {
      if ($1=="type:")    have_type=1
      if ($1=="id:")      have_id=1
      if ($1=="title:")   have_title=1
      if ($1=="status:")  have_status=1
      if ($1=="author:")  have_author=1
      if ($1=="created:") have_created=1
      print; next
    }
    { print }
  ' "$TMP" > "$TMP2"
  mv -f "$TMP2" "$TMP"
else
  TITLE="$(grep -m1 '^# ' "$TMP" | sed 's/^# //' || echo "$SLUG")"
  { printf -- "---\ntype: %s\nid: %s\ntitle: %s\nstatus: queued\nauthor: technoking\ncreated: %s\n---\n" \
      "$TYPE" "$TICKET_ID" "$TITLE" "$(kst_now)"; cat "$TMP"; } > "${TMP}.p"
  mv -f "${TMP}.p" "$TMP"
fi

# ---------- publish ----------------------------------------------------------

mv -f "$TMP" "$DEST"

TMP_REG="${REGISTRY}.$$"
registry_bump "$KEY" "$NEXT" "$TMP_REG"
mv -f "$TMP_REG" "$REGISTRY"

release_lock
echo "published: ${TICKET_ID} path=${DEST}"
