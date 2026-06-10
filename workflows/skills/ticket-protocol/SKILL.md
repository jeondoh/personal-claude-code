---
name: ticket-protocol
description: Schema, lifecycle, naming, and state transitions for every artifact under .claude-team/. Use whenever a persona creates, reads, transitions, or archives a ticket, review report, inbox message, rescue record, backlog item, or handoff. Companion skills - tmux-worker-protocol (delivery), adversarial-review-bridge (rescue), git-flow (branch naming).
---

# Ticket Protocol

`.claude-team/` (gitignored) = transient workflow state, the only handoff medium between panes (markdown + YAML frontmatter). `docs/*` holds user artifacts (see `documentation-criteria`).

## Directory layout

```
.claude-team/
├── tickets/
│   ├── queue/         # published, unclaimed
│   ├── in-progress/   # claimed; also holds in_review status
│   ├── done/          # merged (permanently retained — no archive, no delete)
│   └── cancelled/     # cancelled before merge (auto-archive 7d)
├── reviews/           # Roastmaster review reports (RR-T-*.md, archive 30d after merge)
├── inbox/             # worker → Technoking notifications (transient, deleted on read)
├── rescues/           # codex-rescue tracking (auto-archive 30d)
├── backlog/           # out-of-scope items (BL-NNNN-*.md)
├── handoff/           # /handoff serializations (archive on resume)
├── archive/{YYYY-MM}/ # /cleanup destination
├── workers/
│   └── registry.json  # pane ↔ persona ↔ PID + counters
├── .runtime/          # daemon PIDs/logs, wake.log, <pane>.complete sentinels, <slug>.prompt/.task, verifier dumps (gitignored)
└── config.yml         # /setup-team output (codex verified_at, etc.)
```

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

Numeric counters: **4-digit zero-padded** (`T-0001`), auto-extend to 5 digits past `9999`. Filename `<ID>-<kebab-slug>.md`, slug ≤ 4 words from title. `RR-T-NNNN-N` consumes no counter — `N` is review round (1, 2, 3).

## Frontmatter — common fields (every type; type-specific fields layer on top)

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

```yaml
---
id: T-0042
type: work
title: idempotency key on charge endpoint
status: queued | in_progress | in_review | rescue_candidate | done | cancelled
assignee: persistence-paladin | pixel-wizard | what-if-witch | unassigned   # persona slug — ticket-poll.sh matches by slug
owner: persistence-paladin   # set by ticket-poll.sh at claim time; do not set manually
complexity: small | medium | large
parent_feature: feat/T-0040-charge-idempotency   # umbrella /feat ticket, optional
acceptance_criteria: [AC-001, AC-002, AC-005]
files_in_scope:
  - apps/api/src/payments/charge.kt
  - apps/api/src/payments/idempotency_key.kt
depends_on: [T-0041]                              # other tickets that must merge first
attempt_count: 1                                  # incremented on every build/test invocation (worker)
last_error_signature: a3f8b2e1                    # 8-char SHA-1 of <exception_class>:<failing_bean_or_test>; updated by worker after every failure
last_update_at: 2026-05-11T14:35:00+09:00         # bumped on every build/test invocation or state change (watchdog liveness signal)
protected_files:                                   # worker MUST NOT edit; watchdog fires verification on diff hit
  - src/test/resources/contract/**
  - **/application*.yaml
created: 2026-05-11T14:30:00+09:00
updated: 2026-05-11T14:30:00+09:00
author: technoking
---
```

- `attempt_count` / `last_error_signature` / `last_update_at` are **worker-managed** (Technoking writes none at dispatch). On claim: `attempt_count: 1` + `last_update_at: <now>`. After every build/test failure: overwrite `last_error_signature` + bump `last_update_at` (see `agents/persistence-paladin.md § Workflow step 4`, `agents/pixel-wizard.md § Workflow step 6`). Computed signature == existing → branch to `error_2x` immediately.
- `protected_files` is **Technoking-set at dispatch** for assets that must stay pristine (contract snapshots, production yaml, lockfiles, vendored code, fixtures). Worker MUST NOT edit; fix-required → `status: escalation_needed` (no self-edit). Watchdog diffs the worktree and fires verification on any hit. Globs are worktree-root relative.

### 2. Review report (`type: review-report`)

Filename `RR-T-NNNN-<n>.md` (`<n>` = round); immutable once written; multiple rounds → multiple files. `pattern_stuck: true` triggers auto-rescue (see `adversarial-review-bridge`).

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
error_signature: 8d3c9f1a                         # SHA-1 prefix(8) of <error_class>:<failing_component>
created: 2026-05-11T16:00:00+09:00
---
```

### 3. Rescue record (`type: rescue`)

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

### 4. Review ticket (`type: review`, id `RV-NNNN`)

Two sub-cases share the `RV-NNNN` counter; fields distinguish them.

#### 4a. General PR review (workflow step 9)

```yaml
---
id: RV-0010
type: review
title: review PR #42 round 2
status: queued | in_progress | done
assignee: the-roastmaster   # persona slug; ticket-poll.sh matches by slug
source_ticket: T-0042
pr_number: 42
base_branch: main
round: 2
created: 2026-05-11T18:30:00+09:00
---
```

#### 4b. Rescue validation (codex-rescue patch verification)

Spawned automatically when a codex-rescue patch arrives; top-priority; routed to the original ticket's assignee.

```yaml
---
id: RV-0007
type: review
title: validate rescue patch for T-0042
status: queued | in_progress | done
assignee: persistence-paladin   # persona slug of original ticket's worker
source_ticket: T-0042
source_rescue: RESCUE-20260511T143000+0900
rescue_branch: rescue/T-0042
priority: top
created: 2026-05-11T17:30:00+09:00
---
```

### 5. Inbox message (`type: inbox`)

Worker ↔ Technoking notification or directive; transient (deleted on processing); body free-form, ≤ 200 words.

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

`kind` semantics:
- `directive` — Technoking → worker mid-ticket pivot; targeted worker checks every poll.
- `review_request` — Technoking → worker-review ad-hoc review (reserve; standard path is a queue ticket).
- `review_complete` — worker-review → Technoking verdict delivered (payload: `verdict: APPROVE|COMMENT|BLOCKING`, `report_path`).
- `pattern_stuck` — worker-review → Technoking same BLOCKING repeated; triggers auto-rescue (payload: `blocking_signature`, `rev_count`).
- `fix_pushed` — worker → Technoking BLOCKING fix pushed (payload: `branch`, `last_sha`); Technoking issues round+1 `RV-NNNN`.
- `needs_reblock` — worker → Technoking COMMENT finding escalated to BLOCKING; reason attached.
- `pattern_question` — watchdog → Technoking ambiguous loop/stagnation; **does not auto-kill the worker** — routes to user-decision via Technoking (payload: `pane`, `ticket`, `signals`, `verifier_verdict: ambiguous`, `recommended_action: kill_and_rescue|wait_one_cycle|user_decide`, `evidence_dump_path: .claude-team/.runtime/verifier-<ts>.log`). Technoking presents signals + recommendation via `AskUserQuestion`; never act on a single signal alone.
- `error_2x` — worker self-escalation OR watchdog surrogate after **verifier confirms** confirmed_loop (payload: `error_signature`, `attempt_count`, `failing_test_or_file`, `source: worker|watchdog-surrogate`, optional `verifier_verdict: confirmed_loop`). Triggers `/codex:rescue` per `adversarial-review-bridge §Rescue dispatch pipeline`.
- `escalation_needed` — worker self-escalation OR watchdog surrogate after **verifier confirms** stagnation/timeout (payload: `reason`, optional `verifier_verdict: stagnation`). Technoking handles per `agents/technoking.md §Escalation Coordination`.

### 6. Backlog (`type: backlog`)

Out-of-scope item discovered during work; filed by anyone, processed by Technoking at planning.

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

### 7. Handoff (`type: handoff`)

`/handoff` serialization; body = session summary, decisions, blockers, recommended first action on resume.

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

## State transitions

**Work ticket**:
```
queued → in_progress → in_review → done
                ↘  rescue_candidate → in_progress (after rescue patch)
                ↘  cancelled (any time)
```
- `queued → in_progress`: worker `mv`s file `tickets/queue/` → `tickets/in-progress/`, creates `.worktrees/T-NNNN/`.
- `in_progress → rescue_candidate`: auto-rescue trigger (same error twice, time limit, or attempt limit) → set status, post inbox `kind: error_2x`, stop. File stays in `tickets/in-progress/`.
- `rescue_candidate → in_progress`: Technoking dispatches rescue patch as `RV-NNNN` validation ticket. Worker resumes on rescue branch.
- `in_progress → in_review`: worker pushes branch + posts inbox `kind: completion`. Technoking opens PR. **File stays in `tickets/in-progress/`; only `status` flips.** No separate `in-review/` directory.
- `in_review → done`: PR merged. File moves to `tickets/done/`. Worktree removed.
- `* → cancelled`: explicit `/abort` or scope reset.

**Rescue**:
```
dispatched → patch_received → validation_queued → resolved
                                                ↘  failed (escalation_needed)
```
`failed` never auto-retries; always escalates to user.

**Backlog**:
```
open → promoted (T-NNNN ticket created, BL moved to archive/)  OR  closed (won't fix)
```

## Rescue validation cycle

codex rescue 패치를 검증하는 `RV-NNNN` ticket (sub-case 4b) 절차.

**트리거**: Technoking 이 `/codex:rescue` 결과 직후 `RV-NNNN-<slug>.md` 발행 (type: review, sub-case 4b, priority: top, `rescue_branch: rescue/T-{NNNN}`). 디스패치 흐름 → `adversarial-review-bridge § Rescue dispatch pipeline`.

**워커 절차**:
1. header 에 `rescue_branch` 있으면 RV 검증 모드 (sub-case 4b).
2. `git checkout rescue/T-{NNNN}`.
3. 워커별 quality verification (build / test / typecheck / lint / a11y) — 페르소나 `§ Workflow` 표준 단계와 동일.
4. PASS → ticket `done`, `RESCUE-*` `status: resolved`, 머지 게이트 (Roastmaster 재리뷰) 진입.
5. FAIL → inbox `kind: escalation_needed, reason: rescue_failed` + 사용자 에스컬레이션. **추가 코드 수정 금지.**

**불변 규칙**:
- RV-NNNN (4b) 처리 중 코드 변경 금지 — codex 패치 그대로 검증만.
- `rescue_branch` 없는 RV-NNNN 은 일반 PR review round (4a) — 검증 사이클 아님.
- Rescue 재시도 없음. FAIL 후 동일 ticket·동일 `error_signature` 재디스패치 X (`adversarial-review-bridge § Validation failure — never re-rescue`).

## File operations

- **Dispatch deps**: Technoking checks `depends_on` before dispatching; unresolved-dep tickets stay in `tickets/queue/`, reconsidered each poll. Workers don't check `depends_on` — if it's in their queue, it's ready.
- **Atomicity**: claiming = `mv` file + create worktree + edit frontmatter (`status`, `assignee`, `updated`) in one shell sequence (`mv`, not `git mv` — `.claude-team/` is gitignored). Orphans surfaced by `/cleanup`.
- **Updating**: every state change bumps `updated`. Read full file → modify → write whole file atomically. No in-place sed substitution.
- **Archive**: `/cleanup` archives `cancelled` (>7d), `rescues` (>30d), `reviews` (>30d post-merge) into `archive/{YYYY-MM}/`. **`done` tickets are permanently retained — never archived or deleted, regardless of age.** Archived files retain original IDs/contents — read-only.
- **Concurrency**: multiple workers may sit in `tickets/in-progress/` (different IDs) but cannot touch overlapping `files_in_scope` — Technoking's step-6 decomposition prevents overlap; if unavoidable, sequence via `depends_on`.

## Registry — `workers/registry.json`

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

- **Keys are pane names** (`worker-be`, etc.) — stable across persona renames. `main` (Technoking) is **not** tracked.
- `pid` = **tmux pane PID** (pane's first process, usually the shell that forked `claude`); tracks pane liveness, not claude directly. `pane_id` (e.g. `claude-team:team.2`) is the tmux target for `send-keys`/`select-pane`.
- Counter increment: read → +1 → write, via `ticket-publish.sh`. `RR-`, `RESCUE-`, `HANDOFF-`, `INBOX-` consume no counters.

**Cross-skill**: branch naming → `git-flow`; inbox polling, directive delivery, headless `claude` dispatch → `tmux-worker-protocol`; rescue triggers and validation flow → `adversarial-review-bridge`; 11-step lifecycle → `orchestration-guide`.
