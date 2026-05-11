---
name: ticket-protocol
description: Schema, lifecycle, naming, and state transitions for every artifact under .claude-team/. Use whenever a persona creates, reads, transitions, or archives a ticket, review report, inbox message, rescue record, backlog item, or handoff. Companion skills - tmux-worker-protocol (delivery), adversarial-review-bridge (rescue), git-flow (branch naming).
---

# Ticket Protocol

`.claude-team/` is the project's transient workflow state. Tickets are markdown files with YAML frontmatter; personas read and write them as the only handoff medium between panes.

`docs/*` is for user artifacts (see `documentation-criteria`). `.claude-team/*` is for inter-persona coordination.

## Directory layout

```
.claude-team/
├── tickets/
│   ├── queue/         # published, unclaimed
│   ├── in-progress/   # claimed and being worked (also holds in_review status)
│   ├── done/          # merged (auto-archive 30d)
│   └── cancelled/     # cancelled before merge (auto-archive 7d)
├── reviews/           # Roastmaster review reports (RR-T-*.md, archive 30d after merge)
├── inbox/             # worker → Technoking notifications (transient, deleted on read)
├── rescues/           # codex-rescue tracking (auto-archive 30d)
├── backlog/           # out-of-scope items (BL-NNNN-*.md)
├── handoff/           # /handoff serializations (archive on resume)
├── archive/{YYYY-MM}/ # /cleanup destination
├── workers/
│   └── registry.json  # pane ↔ persona ↔ PID + counters
└── config.yml         # /setup-team output (codex verified_at, etc.)
```

`.claude-team/` is gitignored.

## ID conventions

| Prefix | Meaning | Counter source | Example |
|---|---|---|---|
| `T-` | Work ticket (any type) | `registry.json:counters.T` | `T-0042` |
| `RV-` | Review ticket (PR review or rescue validation) | `registry.json:counters.RV` | `RV-0007` |
| `RR-` | Roastmaster review report | derived from work ticket id | `RR-T-0042-1` (round 1) |
| `BL-` | Backlog (out-of-scope) | `registry.json:counters.BL` | `BL-0019` |
| `RESCUE-` | Rescue dispatch record | timestamp-based | `RESCUE-20260511T143000+0900` |
| `HANDOFF-` | Handoff serialization | timestamp-based | `HANDOFF-20260511T143000+0900` |
| `INBOX-` | Inbox message | timestamp + pane | `INBOX-20260511T143015+0900-worker-be` |

Numeric counters are **4-digit zero-padded** (`T-0001`); auto-extends to 5 digits past `9999`. Filename: `<ID>-<kebab-slug>.md`, slug ≤ 4 words from title. `RR-T-NNNN-N` does not consume a counter — `N` is the review round (1, 2, 3).

## Frontmatter — common fields

Every ticket type carries these; type-specific fields layer on top.

```yaml
---
id: T-0042
type: work | review | review-report | rescue | backlog | handoff | inbox
title: idempotency key on charge endpoint
created: 2026-05-11T14:30:00+09:00      # KST ISO-8601
updated: 2026-05-11T15:45:00+09:00      # bumped on every state change
status: <enum from per-type table below>
author: technoking                      # persona slug
---
```

## Ticket type schemas

### 1. Work ticket (`type: work`)

Created by Technoking in step 6 of `/feat`. Consumed by Paladin / Wizard.

```yaml
---
id: T-0042
type: work
title: idempotency key on charge endpoint
status: queued | in_progress | in_review | done | cancelled
assignee: worker-be | worker-fe | worker-qa | unassigned
complexity: small | medium | large
parent_feature: feat/T-0040-charge-idempotency   # umbrella /feat ticket, optional
acceptance_criteria: [AC-001, AC-002, AC-005]
files_in_scope:
  - apps/api/src/payments/charge.kt
  - apps/api/src/payments/idempotency_key.kt
depends_on: [T-0041]                              # other tickets that must merge first
created: 2026-05-11T14:30:00+09:00
updated: 2026-05-11T14:30:00+09:00
author: technoking
---
```

Body sections (required): **목표**, **수용 기준** (restate AC text), **참조** (Design Doc anchors, ADR links), **테스트 계획**, **완료 정의** (CI, codex review, AC checks).

### 2. Review report (`type: review-report`)

Created by Roastmaster after each review pass. Filename: `RR-T-NNNN-<n>.md` where `<n>` is the review round.

```yaml
---
id: RR-T-0042-1
type: review-report
ticket: T-0042
round: 1
verdict: APPROVE | COMMENT | BLOCKING
reviewer: roastmaster
codex_review_id: <id-from-/codex:result>
pattern_stuck: false                              # true if same BLOCKING as round-(N-1)
error_signature: 8d3c9f1a                         # SHA-1 prefix(8) of <error_class>:<file>:<line>
created: 2026-05-11T16:00:00+09:00
---
```

Body sections (required): **요약** (1–3 sentences), **BLOCKING 이슈** (each: file:line, problem, expected fix), **권장 사항** (non-blocking), **Codex 리뷰 인용** (paste-or-link from `/codex:adversarial-review`).

`pattern_stuck: true` triggers auto-rescue (see `adversarial-review-bridge`). Review reports are immutable once written; multiple rounds produce multiple files.

### 3. Rescue record (`type: rescue`)

Created by Technoking when auto-rescue fires.

```yaml
---
id: RESCUE-20260511T143000+0900
type: rescue
trigger: error_2x | pattern_stuck
source_ticket: T-0042
error_signature: 8d3c9f1a
codex_job_id: <from-/codex:status>
status: dispatched | patch_received | validation_queued | resolved | failed
validation_ticket: RV-0007                        # the RV-NNNN spawned for verifier
created: 2026-05-11T17:00:00+09:00
updated: 2026-05-11T17:30:00+09:00
---
```

Body: short narrative — what triggered, what was dispatched, where the patch landed (`rescue/T-0042` branch), what happened next.

### 4. Review ticket (`type: review`, id `RV-NNNN`)

`type: review` covers two sub-cases; both share the `RV-NNNN` counter. Schema fields distinguish them.

#### 4a. General PR review (workflow step 9)

Issued by Technoking each round. `assignee: worker-review`.

```yaml
---
id: RV-0010
type: review
title: review PR #42 round 2
status: queued | in_progress | done
assignee: worker-review
source_ticket: T-0042
pr_number: 42
base_branch: main
round: 2
created: 2026-05-11T18:30:00+09:00
---
```

Body: PR diff summary + previous round BLOCKING items (if any).

#### 4b. Rescue validation (codex-rescue patch verification)

Spawned automatically when a codex-rescue patch arrives. Top-priority. Routed to the original ticket's assignee.

```yaml
---
id: RV-0007
type: review
title: validate rescue patch for T-0042
status: queued | in_progress | done
assignee: worker-be
source_ticket: T-0042
source_rescue: RESCUE-20260511T143000+0900
branch: rescue/T-0042
priority: top
created: 2026-05-11T17:30:00+09:00
---
```

Body: instructions to merge the rescue branch locally, re-run failing tests, request Roastmaster re-review.

### 5. Inbox message (`type: inbox`)

Worker → Technoking notification, OR Technoking → worker directive. Transient — deleted on processing.

```yaml
---
id: INBOX-20260511T143015+0900-worker-be
type: inbox
from: worker-be | technoking
to: technoking | worker-be | worker-fe | worker-qa | worker-review
ticket: T-0042                                    # optional for directives
kind: progress | escalation_needed | completion | error_2x | pattern_question | directive
    | review_request | review_complete | pattern_stuck | fix_pushed | needs_reblock
escalation_needed: true                           # only when kind == escalation_needed
reason: requirements_change | architectural_change | untestable_ac | codex_unavailable | rescue_failed | codex_review_timeout | other
created: 2026-05-11T14:35:00+09:00
---
```

Body: free-form, ≤ 200 words. `kind: directive` is the channel for mid-ticket pivots from Technoking; the targeted worker checks for these at every poll cycle.

New `kind` values:
- `review_request` — Technoking → worker-review: ad-hoc review request (reserve; standard path is a queue ticket).
- `review_complete` — worker-review → Technoking: verdict delivered (payload: `verdict: APPROVE|COMMENT|BLOCKING`, `report_path`).
- `pattern_stuck` — worker-review → Technoking: same BLOCKING repeated; triggers auto-rescue (payload: `blocking_signature`, `rev_count`).
- `fix_pushed` — worker → Technoking: BLOCKING fix pushed (payload: `branch`, `last_sha`). Technoking issues round+1 `RV-NNNN`.
- `needs_reblock` — worker → Technoking: COMMENT finding escalated to BLOCKING; reason attached.

### 6. Backlog (`type: backlog`)

Out-of-scope item discovered during work. Filed by anyone, processed by Technoking during planning.

```yaml
---
id: BL-0019
type: backlog
title: charge service has 80-line god function
status: open | promoted | closed
discovered_in: T-0042
discovered_by: persistence-paladin
priority: low | medium | high
estimated_complexity: small | medium | large | unknown
created: 2026-05-11T15:00:00+09:00
---
```

Body: what was observed, why it's out of scope for the discovering ticket, suggested approach.

### 7. Handoff (`type: handoff`)

`/handoff` serialization for next session.

```yaml
---
id: HANDOFF-20260511T180000+0900
type: handoff
status: open | resumed
in_flight_tickets: [T-0042, T-0043]
unresolved_inbox: [INBOX-...]
unresolved_rescues: [RESCUE-...]
created: 2026-05-11T18:00:00+09:00
---
```

Body: free-form session summary, decisions, blockers, recommended first action on resume.

## State transitions

### Work ticket

```
queued → in_progress → in_review → done
                ↘  cancelled (any time)
```

- `queued → in_progress`: worker moves file from `tickets/queue/` to `tickets/in-progress/` and creates `.worktrees/T-NNNN/`.
- `in_progress → in_review`: worker pushes branch and posts inbox `kind: completion`. Technoking opens PR. **The file remains in `tickets/in-progress/`; only the `status` field flips.** No separate `in-review/` directory exists.
- `in_review → done`: PR merged. File moves to `tickets/done/`. Worktree removed.
- `* → cancelled`: explicit `/abort` or scope reset.

### Rescue

```
dispatched → patch_received → validation_queued → resolved
                                                ↘  failed (escalation_needed)
```

`failed` never auto-retries. Always escalates to user.

### Backlog

```
open → promoted (T-NNNN ticket created, BL moved to archive/)  OR  closed (won't fix)
```

## Dispatch dependencies

Technoking checks `depends_on` before dispatching: a ticket with unresolved deps stays in `tickets/queue/` and is reconsidered on each poll. Workers do not check `depends_on` themselves — if a ticket is in their pane's queue, it is ready.

## File operations

### Atomicity

A worker claiming a ticket: `mv` the file, create worktree, edit frontmatter (`status`, `assignee`, `updated`) — **in one shell sequence**. (`mv`, not `git mv` — `.claude-team/` is gitignored.) If interrupted mid-claim, `/cleanup` detects orphans (file in `in-progress/` but no worktree, or vice versa) and surfaces to user.

### Updating

Every state change bumps `updated`. Personas write the new frontmatter atomically (read full file → modify → write whole file). No in-place sed substitution.

### Archive

`/cleanup` moves done tickets older than 30d and cancelled older than 7d into `archive/{YYYY-MM}/`. Archived files retain original IDs and contents — read-only.

### Concurrency

Two workers can be in `tickets/in-progress/` simultaneously (different IDs). They cannot work on the same file paths — Technoking's task decomposition (step 6) ensures non-overlapping `files_in_scope`. If overlap is unavoidable, sequence via `depends_on`.

## Counter management — `workers/registry.json`

```json
{
  "counters": { "T": 42, "RV": 7, "BL": 19 },
  "panes": {
    "worker-be":     { "persona": "persistence-paladin", "pid": 12346, "pane_id": "claude-team:team.2" },
    "worker-fe":     { "persona": "pixel-wizard",        "pid": 12347, "pane_id": "claude-team:team.1" },
    "worker-qa":     { "persona": "what-if-witch",       "pid": 12348, "pane_id": "claude-team:team.3" },
    "worker-review": { "persona": "the-roastmaster",     "pid": 12349, "pane_id": "claude-team:team.4" }
  }
}
```

- **Keys are pane names** (`worker-be`, `worker-fe`, `worker-qa`, `worker-review`) — stable identifiers that survive persona renames.
- `pid` is the **tmux pane PID** (the pane's first process — usually the shell that forked `claude`). It tracks pane liveness, not claude's process directly.
- `pane_id` is the tmux target (e.g. `claude-team:team.2`) for `tmux send-keys`/`select-pane`.
- `main` (Technoking) is **not** tracked here — the user's primary pane is implicit.

Counter increment: read → +1 → write, encapsulated by `ticket-publish.sh`. `RR-`, `RESCUE-`, `HANDOFF-`, `INBOX-` prefixes do not consume counters.

## Cross-skill references

- Branch naming derives ticket ID from this skill — see `git-flow`.
- Inbox polling, directive delivery, headless `claude` dispatch — see `tmux-worker-protocol`.
- Rescue triggers and validation flow — see `adversarial-review-bridge`.
- 11-step lifecycle that ties everything together — see `orchestration-guide`.

## When this skill conflicts with the AC

This skill defines the workflow's data model. AC cannot waive frontmatter fields. If an AC seems to require a non-standard field, it goes into the body — frontmatter stays canonical so scripts can rely on it.
