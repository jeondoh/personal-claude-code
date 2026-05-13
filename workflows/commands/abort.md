---
description: Safely cancel in-progress tickets, terminate workers, and clean up worktrees
---

# /abort

Cancel one or all active tickets, signal workers to stop, and reclaim worktrees. No committed work is lost; only uncommitted changes in the worktree are abandoned.

---

## Pre-flight

Verify all three gates in order. Halt on first failure.

1. `.claude-team/config.yml` exists → if not: **halt** — "run `/setup-team` first"
2. `/codex:status` reports ready → if not: **halt** — "run `/codex:setup` first"
3. Every pane PID in `workers/registry.json` is alive → if not: **halt** — "dead worker detected; run `/setup-team` to restart panes"

---

## Arguments

```
/abort <ticket-id>        # cancel a single ticket
/abort --all-active       # cancel all tickets currently in tickets/in-progress/
/abort <ticket-id> --force  # skip worker-response wait (immediate worktree removal)
```

`<ticket-id>` must match `T-\d{4,}` or `RV-\d{4,}`. Any other format → **halt** with format error.

---

## Execution

### Step 1 — Validate ticket state

Confirm `<ticket-id>.md` exists in `.claude-team/tickets/in-progress/`.

- Not found in `in-progress/` → **halt** — "ticket `<id>` is not in-progress; check `tickets/queue/` or `tickets/done/`"
- For `--all-active`: collect all files in `in-progress/`; proceed for each.

### Step 2 — Signal worker (directive)

Technoking identifies the assigned worker pane via `workers/registry.json` (`assignee` field in ticket frontmatter → pane slug → PID).

Technoking publishes a `kind: directive` inbox message (`ticket-protocol § type=inbox`) to `.claude-team/inbox/INBOX-<ts>-<pane>.json`:

```yaml
kind: directive
ticket_id: <id>
action: abort
instruction: "Abort current work. Commit nothing. Return to idle."
```

**Without `--force`**: wait up to 60 s for worker ack (`processed: true`); timeout → proceed and log.  
**With `--force`**: skip wait; proceed immediately to Step 2.5.

> **한계**: directive 는 워커가 idle 폴링 중일 때만 즉시 적용된다. 워커가 이미 claude 인스턴스를 띄워 ticket 을 작업 중이면 directive 는 inbox 에 남아있고, 현재 ticket 종료까지 적용 안 된다. **즉시 중단이 필요하면 `--force` 사용** — 해당 pane 의 claude PID 를 `tmux send-keys C-c` 로 직접 인터럽트.

### Step 2.5 — `--force` 동작 확장

`--force` 사용 시:
1. 60s wait 생략
2. pane registry 에서 claude PID 조회
3. `tmux send-keys -t <pane_id> C-c` 로 SIGINT 전달 (claude 가 우아하게 종료)
4. 2초 후 미반응 시 `kill -TERM <pid>`
5. Step 3 (worktree 제거) 로 진행

### Step 3 — Worktree removal

Reclaim the git worktree associated with the ticket per `git-flow § worktree lifecycle`:

```
git worktree remove --force <worktree-path>
```

Worktree path is derived from `workers/registry.json` or ticket frontmatter `worktree` field.

If worktree path is not found or already removed, log and continue.

### Step 4 — Ticket cancellation

Move ticket file from `tickets/in-progress/` → `tickets/cancelled/`.

Append to ticket frontmatter:

```yaml
cancelled_at: <KST ISO-8601>
cancel_reason: "user invoked /abort"
```

See `ticket-protocol § cancellation`.

### Step 5 — Inbox cleanup

For each processed directive message: set `processed: true` in the inbox file frontmatter. Do not delete (retain for audit). Per `ticket-protocol § inbox lifecycle`.

### Step 6 — Wake daemon teardown (`--all-active` only)

When `--all-active` empties `tickets/in-progress/`, stop the Technoking wake daemons (fswatch + 40s watchdog):

```bash
technoking-daemons.sh stop
```

Single-ticket `/abort <id>` leaves daemons running — other in-flight tickets still need the wake channel. Daemons resume automatically on the next `/setup-team` (idempotent).

---

## Expected Output

```
[/abort complete]
Cancelled : T-NNNN, T-MMMM   (or "none" if --all-active found nothing)
Worktrees : removed <path>, <path>
Timeouts  : <id> (worker did not ack within 60 s)  — omit line if none
```

If halted at pre-flight or argument validation, output the halt reason and corrective action.
