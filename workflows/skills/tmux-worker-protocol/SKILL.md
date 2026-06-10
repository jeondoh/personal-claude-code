---
name: tmux-worker-protocol
description: How tmux panes, headless Claude workers, and inbox-driven dispatch work together. Use whenever a persona launches a worker, sends a message to a pane, polls an inbox, or recovers from a stuck pane. Companion - ticket-protocol (the messages), git-flow (the worktree-per-ticket convention).
---

# Tmux Worker Protocol

Workers are **headless `claude` instances in tmux panes**, isolated in their own worktree, communicating with Technoking exclusively via the file-based ticket protocol. No direct stdin piping between panes.

## Pane layout

```
┌──────────────┬──────────────┐
│              │ worker-fe    │   pane 2
│              ├──────────────┤
│ main         │ worker-be    │   pane 3
│ (Technoking) ├──────────────┤
│   pane 0     │ worker-qa    │   pane 4
├──────────────┤              │
│ worker-      │              │
│ review       │              │
│   pane 1     │              │
└──────────────┴──────────────┘
```

- **Left column (50%)**: `main` (top 60%) / `worker-review` (bottom 40%).
- **Right column (50%)**: `worker-fe` → `worker-be` → `worker-qa` in equal thirds.
- **Pane index is unstable**: tmux numbers panes in layout-tree DFS order (top-down, left-right) and **renumbers on every split**. Reference panes by **name**, the stable identifier in `registry.json` — never by tmux index.
- `Spec Shaman` and `Galaxy Brain` are subagents — no pane, run inside Technoking's `main` via the `Task` tool.

## Pane → persona mapping

```
main          → technoking            (opus)
worker-be     → persistence-paladin   (opus, effort: medium)
worker-fe     → pixel-wizard          (opus, effort: medium)
worker-qa     → what-if-witch         (sonnet)
worker-review → the-roastmaster       (opus)
```

Stored in `.claude-team/workers/registry.json` after `/setup-team`.

## Headless launch — 2-stage architecture

Workers and main use **different launch shapes** to keep the pane chat clean:

- **`main` (Technoking)**: launches `claude --dangerously-skip-permissions` directly — interactive session waits for the user. Persona body from `.claude-team/.runtime/technoking.prompt`; first-message from `.claude-team/.runtime/technoking.task` (short welcome listing common slash commands).
- **`worker-*` (Roastmaster, Wizard, Paladin, Witch)**: launches `worker-idle.sh` — a pure shell polling loop. **No `claude` process while idle.** When a ticket is claimed, the shell execs `claude` with the ticket as first message; when claude exits (via sentinel watchdog, below), the shell resumes polling. Keeps the idle pane log clean (no Bash tool UI, no `Running…`) and costs zero tokens while no tickets are queued.

### `worker-launch.sh`

Encapsulates both launch shapes. The plugin's `bin/` is in PATH — call scripts by bare name, never via `workflows/scripts/...` paths or symlinks. What it does:

1. Strip frontmatter from `agents/<slug>.md`; persist persona body to `.claude-team/.runtime/<slug>.prompt`.
2. **Mode branch**:
   - `main` → write welcome to `.claude-team/.runtime/<slug>.task`; send `claude … "$(cat …task)"` to the pane via `tmux send-keys`. Files read at exec time, avoiding bash 3.2's `printf %q` UTF-8 mangling.
   - `worker-*` → send `worker-idle.sh <slug> <pane-name> <abs-prompt-file>` to the pane. No `.task` file needed.
3. Capture pane PID via `tmux display-message -p '#{pane_pid}'`; (worker panes only) write `{persona, pid, pane_id}` to `registry.json` keyed by **pane name**, atomically (temp → mv, lock-protected). `main` is NOT tracked — implicit.

### `worker-idle.sh` (worker shell loop)

```text
greeting (one-time)
↓
while true:
  poll = ticket-poll.sh <slug>
  if poll == none → sleep 30, repeat
  if poll matched →
    ticket-poll.sh <slug> --claim
    find ticket file in in-progress/ where owner == <slug>
    rm sentinel
    claude --dangerously-skip-permissions --model X \
      --append-system-prompt-file <persona.prompt> \
      "<first-message: read ticket, work it, touch SENTINEL at end>" &
    while claude alive AND sentinel not exists: sleep 3
    when sentinel appears: kill -INT claude (then -TERM)
    loop (back to polling)
```

The first-message instructs claude: **after posting the completion/escalation inbox message, its final Bash tool call must be `touch <.claude-team/.runtime/<pane-name>.complete>`**. The shell watchdog sees the sentinel and kills the claude session, returning the pane to idle. Without this step the worker stays blocked on the current ticket forever.

**Exact CLI flags are owned by `worker-launch.sh` and `worker-idle.sh`** — when Claude Code's headless API changes, only those scripts update. Other skills/personas never embed CLI flags.

Worker's first actions on launch:
1. Read its assigned ticket from `tickets/in-progress/`.
2. Read relevant skills (this skill, `ticket-protocol`, `coding-principles`, etc.).
3. Begin work, or if no ticket assigned, start polling its queue + inbox.

## Inbox-driven dispatch

**No direct messaging** between panes. All coordination is file-based.

### Worker → Technoking

Worker writes `.claude-team/inbox/INBOX-<ts>-<pane-name>.json`:

- `kind: progress` — status update mid-ticket
- `kind: escalation_needed` — blocking issue requiring user or Galaxy Brain (see `ticket-protocol` for `reason` enum)
- `kind: completion` — branch pushed, ready for PR
- `kind: error_2x` — same `error_signature` failed twice → triggers auto-rescue
- `kind: review_complete` — worker-review → Technoking (verdict + report path)
- `kind: pattern_stuck` — worker-review → Technoking (auto-rescue trigger)
- `kind: fix_pushed` — worker → Technoking (BLOCKING fix push complete)
- `kind: needs_reblock` — worker → Technoking (COMMENT escalation request)

### Technoking → Worker

1. **Ticket dispatch (normal work)**: Technoking writes a ticket into `tickets/queue/`; worker discovers it by polling its own queue.
2. **Mid-ticket directive (pivot, abort, refocus)**: inbox message with `to: <pane-name>`, `kind: directive`. Worker checks for `kind: directive` addressed to its pane at every poll cycle and applies immediately. Directives are not work tickets — they instruct *how* to handle the in-flight ticket (e.g., "stop and pivot to T-0050", "drop this approach, see updated AC").
3. **Ad-hoc review request**: `kind: review_request` — Technoking → worker-review (non-standard; queue ticket is the normal path).

> **Directive 한계**: 워커가 ticket 작업 중 (claude 인스턴스 active) 에는 inbox poll 하지 않음 — directive 는 다음 ticket cycle 까지 대기. **즉시 인터럽트가 필요하면** `/abort <T-NNNN> --force` 사용 (pane PID 에 직접 SIGINT 전달).

### No signals, no IPC

Workers receive no `kill`, `SIGUSR1`, or any direct signal. The only notification mechanism is a file existing in `tickets/queue/` or `inbox/`.

### Technoking wake channel (fswatch + watchdog daemon)

The file-only rule extends to Technoking. Two background daemons (launched by `/setup-team` via `technoking-daemons.sh start`) convert filesystem events into Technoking notifications:

| Daemon | Mechanism | Output |
|---|---|---|
| `technoking-watcher.sh` | `fswatch .claude-team/inbox/` | new `INBOX-*.json` paths → `.runtime/wake.log` |
| `technoking-watchdog-daemon.sh` | every 40s: `ticket-watchdog.sh <pane> --dispatch-surrogate` | signal collection + verification → surrogate `INBOX-*.json` (`error_2x` / `escalation_needed` / `pattern_question`, same wake channel); sentinel touched only for confirmed verdicts |

Technoking subscribes via `Monitor(command: 'tail -F -n 0 .claude-team/.runtime/wake.log', persistent: true)`. Each notification = one inbox event. See `agents/technoking.md § Wake Channel`. The IPC-free invariant holds: workers never message Technoking directly — they drop files; fswatch converts files to events.

Lifecycle:
- **Start**: `tmux-setup.sh` calls `technoking-daemons.sh start`. PIDs in `.claude-team/.runtime/{watcher,watchdog}.pid`. Wake log truncated on start.
- **Stop**: `/abort --all-active` or explicit `technoking-daemons.sh stop`.
- **Idempotent restart**: `start` no-ops if already alive; `tmux-setup.sh` re-run heals dead daemons.

Pre-req: `brew install fswatch` (macOS). Daemons preflight-check and exit 2 if missing.

## Polling cycle

When idle (no in-progress ticket), a worker runs a **continuous polling loop** — not a single poll. The model must explicitly run the loop via Bash; pseudo-description is not enough.

### Pseudo-code (semantics)

```
loop every 30 seconds:
  1. read inbox/ for any message with to == self and kind == directive
       → apply directive, continue loop
  2. read tickets/queue/ for any file with assignee == self
  3. read tickets/queue/ for any file with priority == top
       AND (assignee == self OR assignee == unassigned)
  4. if found:
       move to tickets/in-progress/
       update frontmatter (status: in_progress, assignee: self, updated: now)
       create worktree if not exists
       begin work
  5. else:
       sleep
```

### Concrete loop (what the worker actually runs)

```bash
# Batched poll: 10 cycles × 30 s = 5 min wall clock per Bash call.
# Worker calls this repeatedly until a non-"none:" line appears.
for i in $(seq 1 10); do
  out=$(ticket-poll.sh <SLUG> 2>&1)
  echo "[poll $i @ $(TZ=Asia/Seoul date +%H:%M:%S)] $out"
  case "$out" in
    none:*) sleep 30 ;;
    *) break ;;
  esac
done
```

After the Bash call returns:
- Broke on a non-"none:" line → run `ticket-poll.sh <SLUG> --claim` to move the ticket to `in-progress/`, read it, start work per `ticket-protocol`.
- All 10 polls returned "none:" → run the same Bash block again. Do not exit polling.

When in-progress, the worker checks **only** its own ticket and `inbox/` for `kind: directive`. It does not poll for other tickets while occupied.

**Exception (worker-review)**: Roastmaster also polls `kind: review_request` addressed to its pane. See `the-roastmaster.md § Phase A`.

`ticket-poll.sh` is the worker helper (resolved via PATH from the plugin's `bin/`). `worker-launch.sh` injects the concrete loop as the first user message so a fresh worker enters polling immediately.

**While idle, workers must not**: invoke slash commands, explore the codebase, edit files, or call tools other than the Bash polling block. Idle = poll only.

## Sending a message to a pane (manual recovery)

The protocol above is file-only. Single exception: a persona may paste text into another pane's prompt for **interactive nudges** (e.g., "your worker has hung — here's the latest inbox state"). Manual recovery only, not normal flow.

1. Capture recent pane history: `tmux capture-pane -t <pane> -p -S -100` (prevents pasting on top of in-progress work).
2. Clear the input buffer: send `C-u` to the pane.
3. Paste via `tmux send-keys -t <pane> -l <message>`.
4. **Do not press Enter for the user.** Display the message and let the user submit it.

## Worker isolation

Each `worker-*` pane runs inside `.worktrees/<ticket-id>/`, a git worktree off `main`:

- Workers cannot see each other's in-flight changes until merged to `main`.
- Two workers can edit code in parallel if their `files_in_scope` do not overlap.
- The pane's `cwd` is the worktree; tests, builds, formatters operate only on that worktree.

Worktrees are removed on ticket completion (`git worktree remove`). `/abort` and `/cleanup` handle teardown for cancelled or orphaned worktrees.

## Pane lifecycle

| Event | Action |
|---|---|
| `/setup-team` first run | Create panes, write `registry.json`, launch idle workers (no ticket) |
| `/setup-team` re-run | Idempotent — verify pane PIDs, restart dead panes, refresh `updated_at` |
| Pane process dies | `registry.json` goes stale; next `/status` or `/cleanup` detects (PID not alive) and reports |
| `/abort T-NNNN` | Stop worker's current work, release ticket to `cancelled/`, remove worktree, leave pane idle |
| `/cleanup` | Remove orphan worktrees, archive old tickets, refresh `registry.json` |
| Session end | Panes persist across Claude Code sessions (tmux is independent of Claude). Use `/handoff` to serialize logical state |

## Crash recovery

A worker that crashes mid-ticket leaves: a ticket in `tickets/in-progress/` with stale `updated`, a worktree at `.worktrees/T-NNNN/`, possibly partial commits on the feature branch.

Recovery sequence (Technoking, on detection):
1. Read the in-progress ticket and check `updated` age.
2. Pane PID dead → relaunch via `worker-launch.sh` pointing at the same worktree. Worker re-reads the ticket and resumes.
3. Branch has commits but no `kind: completion` reported → ask user: continue, abort, or hand off.

## What workers must NOT do

- Push directly to `main` (only Technoking merges).
- Edit files outside `files_in_scope` (file a `BL-NNNN` instead).
- Read or modify another worker's worktree.
- Skip writing inbox messages on completion or error (Technoking has no other way to know).
- Embed `claude` CLI flags in their own scripts — those live in `worker-launch.sh`.

## When this skill conflicts with the AC

The protocol is the substrate of every ticket — AC cannot waive inbox messages or worktree isolation. If an AC seems to demand it (e.g., "perform this directly on main"), escalate to Technoking; that's a workflow change, not a per-ticket option.
