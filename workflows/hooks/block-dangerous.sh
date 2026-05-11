#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# PreToolUse hook — block destructive Bash commands before Claude executes them.
# Claude Code pipes JSON tool context to stdin; this hook exits 2 to block.
#
# Registered in .claude/settings.local.json:
#   {
#     "hooks": {
#       "PreToolUse": [
#         { "matcher": "Bash",
#           "hooks": [{ "type": "command",
#                       "command": "$CLAUDE_PROJECT_DIR/workflows/hooks/block-dangerous.sh" }] }
#       ]
#     }
#   }
#
# Exit codes: 0=allow, 2=block (Claude Code interprets 2 as hook-blocked)

# --- Read stdin ---
raw_input="$(cat)"

# --- Parse: prefer jq, fall back to python3 ---
parse_json() {
  local field="$1"
  if command -v jq &>/dev/null; then
    printf '%s' "${raw_input}" | jq -r "${field} // empty" 2>/dev/null || true
  elif command -v python3 &>/dev/null; then
    printf '%s' "${raw_input}" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    keys = '${field}'.lstrip('.').split('.')
    v = d
    for k in keys:
        v = v.get(k, '') if isinstance(v, dict) else ''
    print(v if v else '', end='')
except Exception:
    pass
" 2>/dev/null || true
  else
    # No parser available — log warning but allow (fail-open).
    echo "WARNING: block-dangerous.sh: neither jq nor python3 found; skipping check." >&2
    exit 0
  fi
}

tool_name="$(parse_json '.tool_name')"
command_text="$(parse_json '.tool_input.command')"

# --- Only inspect Bash tool calls ---
if [[ "${tool_name}" != "Bash" ]]; then
  exit 0
fi

if [[ -z "${command_text}" ]]; then
  exit 0
fi

# --- Pattern matching ---
block() {
  local reason="$1"
  echo "ERROR: [block-dangerous] Blocked: ${reason}" >&2
  echo "ERROR: [block-dangerous] Command: ${command_text}" >&2
  exit 2
}

# rm -rf targeting absolute paths or broad globs
if echo "${command_text}" | grep -qE '\brm\s+-[rRf]*f[rRf]*\s+/'; then
  block "rm -rf on absolute path is not allowed"
fi

# Git hook bypass
if echo "${command_text}" | grep -qE '\-\-no\-verify'; then
  block "--no-verify bypasses commit hooks"
fi

# Force-push to protected branches (--force or -f)
if echo "${command_text}" | grep -qE 'git\s+push.*--force[^-].*\b(main|master)\b'; then
  block "force-push to main/master is not allowed"
fi
if echo "${command_text}" | grep -qE 'git\s+push.*\s-f\b.*\b(main|master)\b'; then
  block "force-push (-f) to main/master is not allowed"
fi

# chmod 777 on root-level paths
if echo "${command_text}" | grep -qE 'chmod\s+777\s+/'; then
  block "chmod 777 on root-level path is not allowed"
fi

exit 0
