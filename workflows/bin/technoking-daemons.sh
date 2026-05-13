#!/usr/bin/env bash
# technoking-daemons.sh — lifecycle manager for Technoking's wake daemons.
#
# Manages two background daemons:
#   - technoking-watcher.sh        fswatch on inbox/, writes paths to wake.log
#   - technoking-watchdog-daemon.sh  every 40s, surrogate-dispatches stuck-pane INBOX
#
# Started by tmux-setup.sh (called from /setup-team).
# Stopped by /abort --all-active or explicit `technoking-daemons.sh stop`.
#
# Usage: technoking-daemons.sh {start|stop|restart|status}

set -u
IFS=$'\n\t'

CLAUDE_TEAM_DIR="${CLAUDE_TEAM_DIR:-.claude-team}"
RUNTIME="${CLAUDE_TEAM_DIR}/.runtime"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WATCHER_SCRIPT="${SCRIPT_DIR}/technoking-watcher.sh"
WATCHDOG_SCRIPT="${SCRIPT_DIR}/technoking-watchdog-daemon.sh"

WATCHER_PID="${RUNTIME}/watcher.pid"
WATCHDOG_PID="${RUNTIME}/watchdog.pid"
WATCHER_LOG="${RUNTIME}/watcher.log"
WATCHDOG_LOG="${RUNTIME}/watchdog.log"
WAKE_LOG="${RUNTIME}/wake.log"

is_alive() {
  [[ -f "$1" ]] || return 1
  local pid; pid="$(<"$1")"
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

start_one() {
  local name="$1" script="$2" pidfile="$3" logfile="$4"
  if is_alive "$pidfile"; then
    echo "$name: already running (pid $(<"$pidfile"))"
    return 0
  fi
  if [[ ! -x "$script" ]]; then
    echo "$name: ERROR — $script not found or not executable" >&2
    return 1
  fi
  # nohup + detach so the daemon survives the shell that spawned it.
  nohup "$script" </dev/null >>"$logfile" 2>&1 &
  echo $! > "$pidfile"
  echo "$name: started (pid $!)"
}

stop_one() {
  local name="$1" pidfile="$2"
  if ! is_alive "$pidfile"; then
    echo "$name: not running"
    rm -f "$pidfile"
    return 0
  fi
  local pid; pid="$(<"$pidfile")"
  kill "$pid" 2>/dev/null || true
  for _ in 1 2 3 4 5; do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.2
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill -9 "$pid" 2>/dev/null || true
  fi
  rm -f "$pidfile"
  echo "$name: stopped (pid $pid)"
}

status_one() {
  local name="$1" pidfile="$2"
  if is_alive "$pidfile"; then
    echo "$name: alive (pid $(<"$pidfile"))"
  else
    echo "$name: dead"
  fi
}

cmd_start() {
  mkdir -p "$RUNTIME"
  if ! command -v fswatch >/dev/null 2>&1; then
    echo "ERROR: fswatch not installed. Run: brew install fswatch" >&2
    exit 2
  fi
  : > "$WAKE_LOG"   # truncate fresh wake log on session start
  start_one watcher  "$WATCHER_SCRIPT"  "$WATCHER_PID"  "$WATCHER_LOG"
  start_one watchdog "$WATCHDOG_SCRIPT" "$WATCHDOG_PID" "$WATCHDOG_LOG"
}

cmd_stop() {
  stop_one watcher  "$WATCHER_PID"
  stop_one watchdog "$WATCHDOG_PID"
}

cmd_status() {
  status_one watcher  "$WATCHER_PID"
  status_one watchdog "$WATCHDOG_PID"
}

case "${1:-status}" in
  start)   cmd_start ;;
  stop)    cmd_stop ;;
  restart) cmd_stop; cmd_start ;;
  status)  cmd_status ;;
  *) echo "usage: $(basename "$0") {start|stop|restart|status}" >&2; exit 1 ;;
esac
