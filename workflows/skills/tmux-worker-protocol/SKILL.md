---
name: tmux-worker-protocol
description: How tmux panes, headless Claude workers, and inbox-driven dispatch work together. Use whenever a persona launches a worker, sends a message to a pane, polls an inbox, or recovers from a stuck pane. Companion - ticket-protocol (the messages), git-flow (the worktree-per-ticket convention).
---

# Tmux Worker Protocol

Workers are **headless `claude` instances running inside tmux panes**, isolated in their own worktree, communicating with Technoking exclusively via the file-based ticket protocol. No direct stdin piping between panes.

## Pane layout

```
┌──────────────┬──────────────┐
│              │ worker-fe    │
│ main         ├──────────────┤
│ (Technoking) │ worker-be    │
│              ├──────────────┤
├──────────────┤ worker-qa    │
│ worker-      │              │
│ review       │              │
└──────────────┴──────────────┘
```

- **Left (50%)**: `main` (Technoking) / `worker-review` (Roastmaster).
- **Right (50%)**: `worker-fe` (Pixel Wizard) / `worker-be` (Persistence Paladin) / `worker-qa` (What-If Witch).

Pane names are stable identifiers; scripts and `registry.json` reference them by name. `Spec Shaman` and `Galaxy Brain` are subagents only — no pane, run inside Technoking's `main` via the `Task` tool.

## Pane → persona mapping

```
main          → technoking            (sonnet)
worker-be     → persistence-paladin   (sonnet)
worker-fe     → pixel-wizard          (sonnet)
worker-qa     → what-if-witch         (sonnet)
worker-review → the-roastmaster       (opus)
```

Stored in `.claude-team/workers/registry.json` after `/setup-team`.

## Headless launch

Each worker pane runs `claude` interactively (so it can poll continuously) with a persona-loaded prompt and permission prompts disabled. The launch is encapsulated by `worker-launch.sh` (the plugin's `bin/` directory is added to PATH by Claude Code; call scripts by bare name, never with `workflows/scripts/...` paths and never via symlinks). What the script does:

1. Strip frontmatter from `agents/<slug>.md` and persist the persona body to `.claude-team/.runtime/<slug>.prompt` (avoids tmux `send-keys` quoting problems on multi-KB markdown).
2. `tmux send-keys` the launch command into the target pane:
   ```
   claude --dangerously-skip-permissions \
     --model <alias-from-persona-frontmatter> \
     --append-system-prompt-file <abs-path-to-.runtime/<slug>.prompt> \
     '<bootstrap-task>'
   ```
3. Capture the pane's PID via `tmux display-message -p '#{pane_pid}'` and write `{persona, pid, pane_id}` to `.claude-team/workers/registry.json` keyed by **pane name** (`worker-be`, `worker-fe`, …), atomically (temp → mv, lock-protected).

`--dangerously-skip-permissions` is **required** for headless workers — without it, every Bash/Edit tool call stalls on a permission prompt with no human to approve.

**Exact CLI flags are owned by `worker-launch.sh`** — when Claude Code's headless API changes, only that script updates. Other skills and personas do not embed CLI flags.

The worker's first action on launch:

1. Read its assigned ticket from `tickets/in-progress/`.
2. Read the relevant skills (this skill, `ticket-protocol`, `coding-principles`, etc.).
3. Begin work or, if no ticket assigned, start polling its queue + inbox.

## Inbox-driven dispatch

There is **no direct messaging** between panes. All coordination is file-based.

### Worker → Technoking

Worker writes to `.claude-team/inbox/INBOX-<ts>-<pane-name>.md`:

- `kind: progress` — status update mid-ticket
- `kind: escalation_needed` — blocking issue requiring user or Galaxy Brain (see `ticket-protocol` for `reason` enum)
- `kind: completion` — branch pushed, ready for PR
- `kind: error_2x` — same `error_signature` failed twice → triggers auto-rescue
- `kind: pattern_question` — clarification request to Technoking (non-blocking; worker continues on what it can)
- `kind: review_complete` — worker-review → Technoking (verdict + report path)
- `kind: pattern_stuck` — worker-review → Technoking (auto-rescue trigger)
- `kind: fix_pushed` — worker → Technoking (BLOCKING fix push complete)
- `kind: needs_reblock` — worker → Technoking (COMMENT escalation request)

### Technoking → Worker

Two channels:

1. **Ticket dispatch (normal work)**: Technoking writes a ticket file into `tickets/queue/`. The worker discovers it by polling its own queue.
2. **Mid-ticket directive (pivot, abort, refocus)**: Technoking writes an inbox message with `to: <pane-name>`, `kind: directive`. The worker checks for `kind: directive` messages addressed to its pane at every poll cycle and applies them immediately.
3. **Ad-hoc review request**: `kind: review_request` — Technoking → worker-review (non-standard; queue ticket is the normal path).

Directives are not work tickets; they instruct the worker on *how* to handle the in-flight ticket (e.g., "stop and pivot to T-0050", "drop this approach, see updated AC").

### No signals, no IPC

Workers do not receive `kill`, `SIGUSR1`, or any direct signal. The only notification mechanism is a file existing in `tickets/queue/` or `inbox/`.

## Polling cycle

Each worker, when idle (no in-progress ticket), executes a **continuous polling loop** — not a single poll. The model must explicitly run the loop via Bash; pseudo-description is not enough.

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
- If the loop broke on a non-"none:" line → run `ticket-poll.sh <SLUG> --claim` to move the ticket to `in-progress/`, read it, start work per `ticket-protocol`.
- If all 10 polls returned "none:" → run the same Bash block again. Do not exit polling.

When in-progress, the worker checks **only** its own ticket and `inbox/` for `kind: directive`. It does not poll for other tickets while occupied.

**Exception (worker-review)**: Roastmaster also polls `kind: review_request` addressed to its pane. See `the-roastmaster.md § Phase A`.

`ticket-poll.sh` is the helper used by workers (resolved via PATH from the plugin's `bin/`). `worker-launch.sh` injects the concrete loop as the first user message so a fresh worker enters polling immediately.

**While idle, workers must not**: invoke slash commands, explore the codebase, edit files, or call tools other than the Bash polling block. Idle = poll only.

## Sending a message to a pane (manual recovery)

The protocol above is file-only. The single exception: a persona can paste text into another pane's prompt for **interactive nudges** (e.g., "your worker has hung — here's the latest inbox state"). Manual recovery only, not normal flow.

Procedure:

1. Capture recent pane history: `tmux capture-pane -t <pane> -p -S -100`.
2. Clear the input buffer: send `C-u` to the pane.
3. Paste via `tmux send-keys -t <pane> -l <message>`.
4. **Do not press Enter for the user.** Display the message and let the user submit it.

Capturing history first prevents pasting on top of in-progress work.

## Worker isolation

Each `worker-*` pane runs inside `.worktrees/<ticket-id>/`, a git worktree off `main`:

- Workers cannot see each other's in-flight changes until merged to `main`.
- Two workers can edit code in parallel if their `files_in_scope` do not overlap.
- The pane's `cwd` is the worktree; running tests, builds, formatters operates only on that worktree.

Worktrees are removed on ticket completion (`git worktree remove`). `/abort` and `/cleanup` handle teardown for cancelled or orphaned worktrees.

## Pane lifecycle

| Event | Action |
|---|---|
| `/setup-team` first run | Create panes, write `registry.json`, launch idle workers (no ticket) |
| `/setup-team` re-run | Idempotent — verify pane PIDs, restart any dead panes, refresh `updated_at` |
| Pane process dies | `registry.json` gets stale; next `/status` or `/cleanup` detects (PID not alive) and reports |
| `/abort T-NNNN` | Stop worker's current work, release ticket back to `cancelled/`, remove worktree, leave pane idle |
| `/cleanup` | Remove orphan worktrees, archive old tickets, refresh `registry.json` |
| Session end | Panes persist across Claude Code session boundaries (tmux is independent of Claude). Use `/handoff` to serialize logical state |

## Crash recovery

A worker that crashes mid-ticket leaves:

- A ticket in `tickets/in-progress/` with stale `updated`.
- A worktree at `.worktrees/T-NNNN/`.
- Possibly partial commits on the feature branch.

Recovery sequence (Technoking, on detection):

1. Read the in-progress ticket and check `updated` age.
2. If pane PID is dead → relaunch via `worker-launch.sh` pointing at the same worktree. Worker re-reads the ticket and resumes.
3. If branch has commits but worker did not report `kind: completion` → ask user: continue, abort, or hand off.

## What workers must NOT do

- Push directly to `main` (only Technoking merges).
- Edit files outside `files_in_scope` (file a `BL-NNNN` instead).
- Read or modify another worker's worktree.
- Skip writing inbox messages on completion or error (Technoking has no other way to know).
- Embed `claude` CLI flags directly in their own scripts — those live in `worker-launch.sh`.

## When this skill conflicts with the AC

The protocol is the substrate of every ticket — AC cannot waive inbox messages or worktree isolation. If an AC seems to demand it (e.g., "perform this directly on main"), escalate to Technoking; that's a workflow change, not a per-ticket option.
