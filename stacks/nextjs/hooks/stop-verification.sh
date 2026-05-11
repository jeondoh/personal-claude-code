#!/usr/bin/env bash
# Stop hook for the stack-nextjs plugin.
# Claude Code calls this when a worker pane signals end-of-turn. We run the
# canonical Next.js verification (pnpm test) and block on failure (exit 2)
# so a worker cannot claim "done" with red tests.
#
# Skip conditions (silent exit 0):
#   - CLAUDE_TEAM_SKIP_VERIFY=1                 explicit override
#   - no Next.js project at $PWD (no package.json with next dep / no next.config.*)
#   - non-Next worker (other stack's hook will run instead)
#
# Block conditions (exit 2):
#   - pnpm test exits non-zero
#   - pnpm not on PATH inside a Next project (broken setup)
#   - tests exceed VERIFY_TIMEOUT_SEC (default 600s)

set -euo pipefail
IFS=$'\n\t'

readonly VERIFY_TIMEOUT_SEC="${VERIFY_TIMEOUT_SEC:-600}"

# Drain stdin (Claude Code Stop-hook context). We do not parse it.
[[ -t 0 ]] || cat >/dev/null 2>&1 || true

if [[ "${CLAUDE_TEAM_SKIP_VERIFY:-0}" == "1" ]]; then
  echo "stop-verification (nextjs): skipped via CLAUDE_TEAM_SKIP_VERIFY=1" >&2
  exit 0
fi

# Detect Next.js project. Either a next.config.* or a package.json declaring next.
is_next_project=0
if [[ -f next.config.js || -f next.config.mjs || -f next.config.ts ]]; then
  is_next_project=1
elif [[ -f package.json ]] && grep -qE '"next"\s*:\s*"' package.json; then
  is_next_project=1
fi

if [[ "${is_next_project}" -ne 1 ]]; then
  # Not a Next project — quietly defer to whichever stack hook applies.
  exit 0
fi

# Require pnpm — the team's canonical package manager (pinned in stacks/nextjs/skills).
if ! command -v pnpm >/dev/null 2>&1; then
  echo "stop-verification (nextjs): pnpm not on PATH" >&2
  echo "  the canonical command is pnpm test — install pnpm 9+ or fix PATH" >&2
  exit 2
fi

# Confirm a test script exists. If not, the project's testing setup is broken
# (testing-nextjs skill mandates a test runner). Block so the user notices.
if ! grep -qE '"test"\s*:\s*"' package.json; then
  echo "stop-verification (nextjs): no \"test\" script in package.json" >&2
  echo "  add a test runner per testing-nextjs skill (vitest/jest/playwright)" >&2
  exit 2
fi

extra_args="${VERIFY_PNPM_ARGS:-}"
echo "stop-verification (nextjs): running pnpm test ${extra_args}" >&2

if command -v timeout >/dev/null 2>&1; then
  if timeout --kill-after=30s "${VERIFY_TIMEOUT_SEC}" pnpm test ${extra_args} >&2; then
    exit 0
  else
    rc=$?
    echo "stop-verification (nextjs): pnpm test failed (rc=${rc})" >&2
    exit 2
  fi
fi

# Fallback (no `timeout` binary on PATH — common on macOS without coreutils).
pnpm test ${extra_args} >&2 &
pnpm_pid=$!
( sleep "${VERIFY_TIMEOUT_SEC}" && kill -TERM "${pnpm_pid}" 2>/dev/null || true ) &
watcher_pid=$!
if wait "${pnpm_pid}"; then
  kill -TERM "${watcher_pid}" 2>/dev/null || true
  exit 0
else
  rc=$?
  kill -TERM "${watcher_pid}" 2>/dev/null || true
  echo "stop-verification (nextjs): pnpm test failed (rc=${rc})" >&2
  exit 2
fi
