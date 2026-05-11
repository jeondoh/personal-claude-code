---
description: Run a small single-purpose change or bug fix (1–2 files, single area, no DB / no auth)
---

# /task

Execute a scoped, low-risk change with the full quality gate (review + rescue) but minimal ceremony.

---

## Pre-flight

Before any action, verify all three gates in order. Halt on first failure.

1. `.claude-team/config.yml` exists → if not: **halt** — "run `/setup-team` first"
2. `/codex:status` reports ready → if not: **halt** — "run `/codex:setup` first"
3. Every pane PID in `workers/registry.json` is alive → if not: **halt** — "dead worker detected; run `/setup-team` to restart panes"

---

## Execution

### Step 1 — Complexity gate (Technoking)

Technoking evaluates the request against the complexity table in `orchestration-guide`:

| Signal | Decision |
|--------|----------|
| 1–2 files, single area, no DB/API/auth/deps change | ✅ proceed as `small` |
| Anything else | ❌ **halt** — "complexity is not `small`; use `/feat` instead" |

Immediate large triggers (from BUILD-PROGRESS design decisions): auth/permission change, DB schema migration, new domain, external payment/legal → auto-escalate without negotiation.

### Step 2 — Worker ticket

Technoking issues one `type: work, complexity: small` ticket per `ticket-protocol § type=work`.

- Assign to **Persistence Paladin** for backend-only changes, **Pixel Wizard** for frontend-only.
- If ambiguous, default to Paladin.
- Counter: increment `T` in `workers/registry.json` (4-digit zero-pad).
- Place ticket in `.claude-team/tickets/queue/`.

### Step 3 — /task shortcut execution

Technoking runs the `/task` 3-step shortcut from `orchestration-guide § /task shortcut`:

1. **Implement** — assigned worker picks up ticket, moves to `in-progress/`, opens worktree (`git-flow § worktree lifecycle`), implements change, commits.
2. **PR + review** — Technoking opens PR; Roastmaster dispatches `/codex:adversarial-review --background` (mandatory, non-blocking; codex is sole reviewer; see `adversarial-review-bridge § quality gates`). Max 3 review rounds. Each finalized report stored as `RR-T-NNNN-<round>.md`.
3. **Merge** — Technoking merges on Roastmaster ✅ (no pre-merge Stop for `small`). Ticket moved to `done/`.

### Step 4 — Auto-rescue (always active)

Same gates as `/feat`, triggered automatically by Technoking:

- Same error signature twice → `/codex:rescue --background` → new `RV-NNNN` validation ticket (queue priority).
- Roastmaster `pattern_stuck: true` (same BLOCKING comment 2 rounds) → rescue.
- Rescue validation fail → `escalation_needed`, stop + user notification.

See `adversarial-review-bridge § quality gates` and `ticket-protocol § rescue flow`.

---

## Expected Output

```
[/task complete]
Ticket  : T-NNNN — <title>
Worker  : <Paladin|Wizard>
PR      : <branch> → main
Review  : RR-T-NNNN-1.md ✅ (round 1)
Rescue  : none | RV-NNNN (patch applied)
Status  : merged ✅
```

If halted at complexity gate or pre-flight, output the halt reason and the corrective command.
