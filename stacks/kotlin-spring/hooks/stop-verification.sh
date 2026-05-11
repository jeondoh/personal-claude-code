#!/usr/bin/env bash
# Stop hook for the stack-kotlin-spring plugin.
# Claude Code calls this when a worker pane signals end-of-turn. We run the
# canonical Kotlin/Spring build verification (./gradlew test) and block on
# failure (exit 2) so a worker cannot claim "done" with red tests.
#
# Skip conditions (silent exit 0):
#   - CLAUDE_TEAM_SKIP_VERIFY=1                 explicit override
#   - no Gradle project at $PWD (no build.gradle.kts / settings.gradle.kts)
#   - non-Kotlin worker (other stack's hook will run instead)
#
# Block conditions (exit 2):
#   - ./gradlew test exits non-zero
#   - ./gradlew not present in a Gradle project (broken setup)
#   - tests run but exceed VERIFY_TIMEOUT_SEC (default 600s)

set -euo pipefail
IFS=$'\n\t'

readonly VERIFY_TIMEOUT_SEC="${VERIFY_TIMEOUT_SEC:-600}"

# Drain stdin (Claude Code Stop-hook context). We do not parse it — the cwd is
# the worker's worktree, which is all we need.
[[ -t 0 ]] || cat >/dev/null 2>&1 || true

if [[ "${CLAUDE_TEAM_SKIP_VERIFY:-0}" == "1" ]]; then
  echo "stop-verification (kotlin): skipped via CLAUDE_TEAM_SKIP_VERIFY=1" >&2
  exit 0
fi

# Detect Gradle project. Either marker file is enough.
if [[ ! -f build.gradle.kts && ! -f settings.gradle.kts && ! -f build.gradle && ! -f settings.gradle ]]; then
  # Not a Gradle project — quietly defer to whichever stack hook applies.
  exit 0
fi

# Confirm the wrapper exists. Without it the team's "canonical command"
# contract is violated; treat as block so the user notices.
if [[ ! -x ./gradlew ]]; then
  echo "stop-verification (kotlin): ./gradlew not found or not executable in $PWD" >&2
  echo "  the canonical build entry point is ./gradlew test — fix the project layout" >&2
  exit 2
fi

# Run the canonical test command with a wall-clock timeout.
# Honor an optional --offline / --no-daemon override via VERIFY_GRADLE_ARGS.
extra_args="${VERIFY_GRADLE_ARGS:-}"

echo "stop-verification (kotlin): running ./gradlew test ${extra_args}" >&2

# `timeout` may not exist on macOS (BSD) without coreutils. Fall back to a
# background-and-wait pattern when missing.
if command -v timeout >/dev/null 2>&1; then
  if timeout --kill-after=30s "${VERIFY_TIMEOUT_SEC}" ./gradlew test ${extra_args} >&2; then
    exit 0
  else
    rc=$?
    echo "stop-verification (kotlin): ./gradlew test failed (rc=${rc})" >&2
    exit 2
  fi
fi

# Fallback path (no `timeout` binary).
./gradlew test ${extra_args} >&2 &
gradle_pid=$!
( sleep "${VERIFY_TIMEOUT_SEC}" && kill -TERM "${gradle_pid}" 2>/dev/null || true ) &
watcher_pid=$!
if wait "${gradle_pid}"; then
  kill -TERM "${watcher_pid}" 2>/dev/null || true
  exit 0
else
  rc=$?
  kill -TERM "${watcher_pid}" 2>/dev/null || true
  echo "stop-verification (kotlin): ./gradlew test failed (rc=${rc})" >&2
  exit 2
fi
