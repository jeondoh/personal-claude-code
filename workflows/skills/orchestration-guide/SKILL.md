---
name: orchestration-guide
description: Master playbook for Technoking. Defines the 11-step /feat lifecycle, complexity verdict rules, Stop policy, automatic escalation rules, and how all other workflows skills compose. Use whenever Technoking accepts a new request, dispatches workers, runs the review/rescue loop, or merges. Companion - ticket-protocol (data model), tmux-worker-protocol (delivery), adversarial-review-bridge (codex), git-flow (branches), documentation-criteria (docs), coding-principles + testing-principles (quality bars).
---

# Orchestration Guide

Technoking's master playbook. Other personas read it for context; Technoking owns the lifecycle.

`/feat` is 11 steps. `/task` is a 3-step shortcut for verified-small work. Both share the same quality gates (Roastmaster review + codex adversarial review + auto-rescue, see `adversarial-review-bridge`).

## Pre-flight (every command)

Before accepting any user request:

1. Verify `.claude-team/config.yml` exists (i.e., `/setup-team` has been run).
2. Verify `/codex:status` is healthy (codex is hard dependency).
3. Verify panes are alive per `registry.json`.

If any check fails, halt: "run `/setup-team` first" or "run `/codex:setup` first." Do not proceed.

## Complexity verdict — step 1 of every lifecycle

| Verdict | Rule | Routing |
|---|---|---|
| **small** | 1–2 files, single area, no DB / no API surface change / no auth / no new dependency | `/task` 3-step path |
| **medium** | 3–5 files, small DB change OR 1–2 new API endpoints, within an existing domain | `/feat` lifecycle (1 Stop, merged spec) |
| **large** | 6+ files, both backend and frontend, large DB change, new domain, OR external integration | `/feat` lifecycle (3 Stops, separate docs) |

### Auto-large triggers (override the above)

Any of these forces `large` regardless of file count:

- AuthN / AuthZ / permission model change
- DB schema migration (add table, drop column, change constraint)
- New domain (a new bounded context being introduced)
- External payment provider, regulatory or compliance scope change

### Auto-escalation mid-flight

Re-evaluate complexity at every step. If newly discovered facts trip an auto-large trigger, escalate the in-flight `medium` to `large`:

- Split the merged PRD+Design into separate docs from this point forward (do not retrofit history).
- Insert the missed Stops (e.g., catch up to step 3 PRD-approval Stop if not yet taken).
- Update the umbrella ticket's `complexity` field and notify the user.

## `/feat` 11-step lifecycle (Stop policy = B-pattern)

| Step | Owner | Output | Stop? (small/medium/large) |
|---|---|---|---|
| 1. Intake + complexity verdict | Technoking | complexity recorded, route decided | — / — / — |
| 2. PRD draft | Spec Shaman (subagent) | `docs/prd/*-prd.md` (large) or merged spec section | — |
| 3. PRD approval | user | sign-off | — / — / **Stop** |
| 4. Design + ADR + interfaces | Galaxy Brain (subagent) | `docs/design/*.md`, `docs/adr/ADR-NNNN-*.md` | — |
| 5. Design + interface approval | user | sign-off | — / **Stop (PRD+Design merged)** / **Stop** |
| 6. Task decomposition + ticket batch | Technoking | `T-NNNN` tickets in `tickets/queue/` | — / — / **Stop (batch approval)** |
| 7. Acceptance tests (fail-first) | What-If Witch | failing tests committed to feature branch | — |
| 8. Implementation (parallel) | Paladin + Wizard | code committed, tests passing | — |
| 9. PR + review loop (max 3 rounds) | Technoking → Roastmaster | review reports `RR-T-NNNN-<n>.md`, codex adversarial review | — |
| 10. Integration + E2E (large default; medium if AC requires) | What-If Witch | green CI, integration assertions pass | — |
| 11. Merge + report | Technoking | squash merge, ticket `done`, completion summary | — |

After step 6's batch approval (large) or step 5's merged approval (medium), execution from step 7 onward is **autonomous** — no merge-time Stop. The user can interrupt anytime; absence of interruption is implicit consent.

### `/task` 3-step shortcut (small only)

| Step | Owner | Output | Stop? |
|---|---|---|---|
| 1. Implementation | Paladin or Wizard (one worker) | code + tests committed | — |
| 2. PR + review loop (max 3 rounds) | Technoking → Roastmaster | RR reports, codex review | — |
| 3. Merge + report | Technoking | merge, ticket `done` | — |

`/task` skips PRD, Design, ADR, decomposition, parallel work, and integration testing. It does **not** skip Roastmaster review or codex adversarial review or auto-rescue. Quality gates are uniform.

## Quality gates — apply to every ticket regardless of complexity

Invariant across `/feat` and `/task`, small/medium/large:

1. `/codex:adversarial-review --background` per PR (codex is sole reviewer).
2. Roastmaster (opus) judges the codex result — uphold / downgrade BLOCKING → COMMENT / escalate. Never walks the diff itself.
3. Auto-rescue on `error_2x` or `pattern_stuck` (see `adversarial-review-bridge`).
4. All AC checkboxes pass.
5. CI green (build, lint, type check, tests).
6. PR within size limits (`git-flow`: 400 soft / 800 hard).

Roastmaster's authority is final. A BLOCKING from Roastmaster halts merge until resolved or escalated.

## Worker escalation invariants

Workers must never get stuck in a silent retry loop. **Four** triggers fire `kind: error_2x` immediately (no debug retry), plus a Technoking-side safety net. Persona bodies (`persistence-paladin`, `pixel-wizard`, `what-if-witch`) all evaluate the same four triggers — values consolidated here are canonical.

| # | Trigger | Threshold | Detected by |
|---|---|---|---|
| 1 | `error_2x` — same `error_signature` repeats | After every build/test invocation; match against `last_error_signature` (formula in `adversarial-review-bridge § Error signature`) | Worker, before any further code edit |
| 2 | `timeout` — elapsed since `started` | **> 20 min** with unresolved failure (all workers) | Worker |
| 3 | `attempt_limit` — `attempt_count` | **≥ 3** with ongoing failure | Worker (every build/test = 1 attempt) |
| 4 | `context_pressure` — worker's own context | **> 80%** while a failure is unresolved | Worker (pre-empt before judgment degrades) |

The retry unit is **one build/test command execution**, not a logical "cycle." Any trigger → worker writes inbox `kind: error_2x` with `reason: build_loop|timeout|attempt_limit|context_pressure` and halts.

**Safety net — background watchdog daemon (v2)**: `technoking-watchdog-daemon.sh` (launched by `/setup-team`) calls `ticket-watchdog.sh <pane> --dispatch-surrogate` against every worker pane every 40s. The probe collects 6 signals (`error_loop`, `rev_repeat`, `rev_idle`, `last_update_stale`, `protected_breach`, `worktree_stagnation`), verifies, and classifies as `protected_breach` / `confirmed_loop` / `stagnation` / `ambiguous`. Confirmed verdicts auto-publish the kind-specific surrogate INBOX (`escalation_needed` / `error_2x` / `escalation_needed`) **and** touch `.runtime/<pane>.complete`; `ambiguous` publishes `pattern_question` **without** sentinel — the worker stays alive and Technoking surfaces the evidence to the user via `AskUserQuestion`. **Technoking does not call the watchdog manually** — see `agents/technoking.md § Watchdog detection`.

Triggers 1–4 are the worker's responsibility; the watchdog is Technoking's safety net when they misfire.

## Stop policy details

### Stop format

```
[Stop — <step name>]

이번에 정하는 것: <one sentence>

추천: <option + rationale>

대안:
- <option B>: <rationale>
- <option C>: <rationale>

승인하시면 다음 단계로 진행합니다.
```

### Batch approval (step 6, large only)

The decomposed ticket batch is approved as a set, not ticket-by-ticket. Approval format includes the full ticket list with `id`, `title`, `assignee`, `complexity`, `depends_on`. After approval, Technoking executes through step 11 without further user gates (modulo escalations).

### Forced escalations (Stop regardless of policy)

The following force a Stop even outside scheduled Stop points:

- Worker emits `kind: escalation_needed` with reason `requirements_change | architectural_change | untestable_ac`.
- Mid-flight auto-escalation to `large` (see "Auto-escalation mid-flight").
- 3rd consecutive review BLOCKING in step 9 (max review rounds reached).
- Rescue validation fails (`reason: rescue_failed`).
- Codex unavailable (`reason: codex_unavailable`) — pre-flight catches this; if it appears mid-flight:
  - **Halt** all new codex dispatches (adversarial-review + rescue). Do not attempt degraded-mode review.
  - In-flight implementation workers **continue** (they don't depend on codex directly).
  - Notify user immediately: "codex 다운 — PR 리뷰/rescue 대기 중. `/codex:setup` 재실행 후 알려주세요."
  - Resume codex steps once `/codex:status` returns `ready`. **Do not merge without completed codex review.**

## Step-by-step operational notes

### Step 1 — Intake

- Classify complexity per rule table.
- Create umbrella ticket (`type: work`) in `tickets/queue/`, assignee `unassigned`. Move to `in-progress/` on start.

### Step 2 — PRD

- Dispatch Spec Shaman as subagent (Agent tool) — runs inline in `main`.
- PRD per `documentation-criteria`. `medium` → merged spec section, not own file.

### Step 4 — Design

- Dispatch Galaxy Brain as subagent (Agent tool) — runs inline in `main`.
- Galaxy Brain reads `documentation-criteria` + `coding-principles`. ADRs per trigger rules.

### Step 6 — Task decomposition

- Non-overlapping `files_in_scope`. Overlap → sequence via `depends_on`. Ticket ≤ ~400 LOC diff.
- `medium`: 1–2 tickets inline (no Stop). `large`: batch with approval Stop.

### Step 7 — Fail-first acceptance tests

- What-If Witch writes one acceptance test per AC, committed red before step 8.
- Untestable AC → `escalation_needed: untestable_ac`.

### Step 8 — Parallel implementation

- **Dispatch (file-based)**: write tickets to `tickets/queue/` with `assignee: <persona-slug>` (e.g., `persistence-paladin`, not `worker-be`). Workers self-poll every 30 s via `ticket-poll.sh`. No `tmux send-keys` for dispatch.
- **Inbox check before next batch**: any `error_2x` / `pattern_stuck` → rescue first.
- Worker worktrees `.worktrees/T-{NNN}/`. `kind: progress` = info; `kind: completion` = branch pushed.

### Step 9 — Review loop

- Technoking opens PR (`git-flow` template), dispatches review ticket to `worker-review`.
- Roastmaster dispatches `/codex:adversarial-review --background` (sole reviewer), writes `codex_pending` `RR-T-NNNN-<round>.md`, returns to queue — never blocks. See `adversarial-review-bridge` § non-blocking invariants.
- Next turn: Roastmaster judges codex result (uphold/downgrade), finalizes verdict.

| Verdict | Effect |
|---|---|
| `APPROVE` | Step 10 (or 11). Merge unblocked. |
| `COMMENT` | Non-blocking. Inline fixes; material follow-ups → `BL-NNNN`. |
| `BLOCKING` | Merge halted. Fix-and-rereview round; counts toward limit. |

BLOCKING flow: `review_complete`(BLOCKING) → directive → fix → `fix_pushed` → new `RV-NNNN` (`round: prev+1`, schema `ticket-protocol § 4a`) → Roastmaster Phase A.
COMMENT flow: worker inline-pushes; `kind: needs_reblock` upgrades to BLOCKING.
Auto-rescue (see `adversarial-review-bridge`) may fire mid-loop. Hard limit: 3 BLOCKING rounds → escalate.

### Step 10 — Integration + E2E

- `large` default; `medium` per AC. What-If Witch runs integration suite.
- Max 2 retries → escalate.

### Step 11 — Merge

- Pre-merge checklist (`git-flow`). Squash to `main`, move ticket → `done/`, remove worktree, post completion summary.

## Composition map

When confused about which skill to consult:

| Question | Skill |
|---|---|
| What goes in a ticket file? | `ticket-protocol` |
| How do I message a pane? | `tmux-worker-protocol` (file-based, no direct IPC) |
| How do I invoke codex? | `adversarial-review-bridge` |
| How do I name a branch / write a commit / open a PR? | `git-flow` |
| What's required in a PRD / Design / ADR? | `documentation-criteria` |
| Code-quality rules? | `coding-principles` |
| Test rules? | `testing-principles` |
| Stack-specific (Kotlin/Spring, Next.js)? | `stack-*` plugin skills |

## When this skill conflicts with the AC

The lifecycle is the workflow's invariant. AC cannot waive Stop steps, review loops, or rescue policy. Per-ticket exceptions are escalations, not configurations.
