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

## Stop policy details

### Stop format

When a Stop point is reached, Technoking writes a clear approval prompt:

```
[Stop — <step name>]

이번에 정하는 것: <one sentence>

추천: <option + rationale>

대안:
- <option B>: <one-line rationale>
- <option C>: <one-line rationale>

승인하시면 다음 단계로 진행합니다. 변경 원하시면 알려주세요.
```

### Batch approval (step 6, large only)

The decomposed ticket batch is approved as a set, not ticket-by-ticket. Approval format includes the full ticket list with `id`, `title`, `assignee`, `complexity`, `depends_on`. After approval, Technoking executes through step 11 without further user gates (modulo escalations).

### Forced escalations (Stop regardless of policy)

The following force a Stop even outside scheduled Stop points:

- Worker emits `kind: escalation_needed` with reason `requirements_change | architectural_change | untestable_ac`.
- Mid-flight auto-escalation to `large` (see "Auto-escalation mid-flight").
- 3rd consecutive review BLOCKING in step 9 (max review rounds reached).
- Rescue validation fails (`reason: rescue_failed`).
- Codex unavailable (`reason: codex_unavailable`) — pre-flight catches this; if it appears mid-flight, halt.

## Step-by-step operational notes

### Step 1 — Intake

- Read user prompt, classify complexity using the rule table.
- Create umbrella ticket (`type: work` for the parent `/feat`) in `tickets/queue/`. Assignee: `unassigned`.
- Move it to `in-progress/` once Technoking starts working it.

### Step 2 — PRD

- Dispatch Spec Shaman as a subagent (Task tool).
- Spec Shaman reads `documentation-criteria` and writes the PRD per that skill's spec.
- For `medium`, the PRD lives as a section in the merged spec, not its own file.

### Step 4 — Design

- Dispatch Galaxy Brain as a subagent.
- Galaxy Brain reads `documentation-criteria`, then `coding-principles`, before designing.
- ADRs created per the trigger rules in `documentation-criteria`.

### Step 6 — Task decomposition

- Goal: non-overlapping tickets where each ticket's `files_in_scope` doesn't collide with another. If overlap is unavoidable, sequence via `depends_on`.
- Each ticket sized for one worker, ≤ ~400 lines of expected diff.
- For `medium`, decomposition often yields 1–2 tickets and is performed inline (no Stop).
- For `large`, decomposition produces a batch. The Stop step is the batch approval.

### Step 7 — Fail-first acceptance tests

- What-If Witch reads the AC list from PRD/Design and writes one acceptance test per AC.
- Tests committed to the feature branch in red state before Paladin/Wizard begin step 8.
- An AC that cannot be expressed as a test triggers `escalation_needed: untestable_ac`.

### Step 8 — Parallel implementation

- Worker tickets land in their pane queues per `assignee`.
- Workers operate independently in their worktrees.
- Workers may emit progress inbox messages; Technoking does not micromanage.
- A worker reaching `kind: completion` indicates branch is pushed.

### Step 9 — Review loop

- Technoking opens PR using `git-flow`'s template.
- Technoking dispatches a review ticket to `worker-review` pane.
- Roastmaster dispatches `/codex:adversarial-review --background` (codex is sole reviewer; Roastmaster does **not** walk the diff). Writes a `codex_pending` placeholder `RR-T-NNNN-<round>.md`, then **returns to the queue** to handle other reviews or pending jobs — never blocks. See `adversarial-review-bridge` § "Non-blocking dispatch — invariants".
- On result arrival (next Roastmaster turn), Roastmaster judges the findings — uphold or downgrade — and finalizes the report with verdict.
- Verdict semantics:

| Verdict | Effect |
|---|---|
| `APPROVE` | Proceed to step 10 (or step 11 if step 10 is skipped per AC). Merge unblocked. |
| `COMMENT` | Non-blocking. Merge may proceed. Workers address comments inline; material follow-ups become `BL-NNNN`. |
| `BLOCKING` | Merge halted. Workers fix and push, Roastmaster re-reviews. Counts toward the round limit. |

On BLOCKING:
  1. Roastmaster sends inbox `kind: review_complete` (verdict=BLOCKING, report path).
  2. Technoking sends `kind: directive` to worker pane (fix instructions citing BLOCKING items).
  3. Worker fixes on the same branch, pushes, emits `kind: fix_pushed`.
  4. Technoking publishes a new `type: review` ticket (`RV-NNNN`, `round: prev+1`, schema per `ticket-protocol § 4a`) into `tickets/queue/`.
  5. Roastmaster Phase A picks it up; new round begins.

On COMMENT:
  - Worker inline edits push to the same branch without triggering a new round.
  - Material follow-ups become `BL-NNNN`.
  - If the worker judges the comment merits a blocking re-review, emit `kind: needs_reblock`; Technoking upgrades to BLOCKING and follows the flow above (round+1 ticket).

- Auto-rescue triggers (see `adversarial-review-bridge`) may fire mid-loop.
- Hard limit: 3 BLOCKING rounds. After round 3 BLOCKING, escalate to user.

### Step 10 — Integration + E2E

- Default for `large`. Optional for `medium` (driven by AC's verification strategy).
- What-If Witch validates against integration test suite.
- Up to 2 retry rounds. After 2 failures, escalate.

### Step 11 — Merge

- Technoking enforces pre-merge checklist (`git-flow`).
- Squash merge to `main`.
- Move ticket to `tickets/done/`.
- Remove worktree.
- Write completion summary in inbox or directly to user.

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
