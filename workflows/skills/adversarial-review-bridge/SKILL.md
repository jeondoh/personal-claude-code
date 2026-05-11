---
name: adversarial-review-bridge
description: Bridge between the workflows plugin and openai/codex-plugin-cc. Defines when and how to invoke /codex:adversarial-review and /codex:rescue, the auto-rescue triggers, error_signature calculation, and the rescue→validation→re-review pipeline. Use whenever Roastmaster reviews a PR, Technoking dispatches a rescue, or a worker validates a rescue patch.
---

# Adversarial Review Bridge

Single source of truth for our integration with **openai/codex-plugin-cc**. The codex plugin is a **hard dependency** — verified by `/setup-team` before any ticket runs.

If anything here changes (codex plugin renames a command, etc.), update this file. Personas and other skills consult this skill, not embed the codex contract themselves.

## Codex commands we use

| Command | Owner | Purpose |
|---|---|---|
| `/codex:setup` | user (one-time) | Install codex CLI + authenticate |
| `/codex:status` | Technoking, scripts | Health check; called by `/setup-team` and before each rescue dispatch |
| `/codex:adversarial-review` | Roastmaster | Invoke codex as adversarial reviewer on a PR or branch |
| `/codex:rescue` | Technoking | Dispatch a background fix-it job for a stuck ticket |
| `/codex:result` | any persona | Retrieve output of a previous codex job by id |
| `/codex:cancel` | Technoking, `/abort` | Cancel an in-flight codex job |
| `/codex:review` | (unused by us) | We use the adversarial variant exclusively |

## Pre-flight — every codex call

Before any codex command, the calling persona runs `/codex:status`. If status is anything other than ready, the persona writes an inbox message (`kind: escalation_needed`, `reason: codex_unavailable`) and halts. No degraded mode.

## When Roastmaster invokes adversarial-review

**Every PR, every round.** No complexity-based skipping. **Codex is the sole reviewer** — Roastmaster does not walk the diff itself; it dispatches, waits non-blockingly, then judges the codex result.

Step 9 of the `/feat` lifecycle (and equivalent in `/task`):

1. Technoking opens PR.
2. Worker-review pane (Roastmaster) is dispatched a review ticket.
3. Roastmaster — **non-blocking dispatch**:
   - Invokes `/codex:adversarial-review --background` against the PR branch. Capture the returned `codex_job_id`.
   - Writes a placeholder `RR-T-NNNN-<round>.md` with `status: codex_pending`, `codex_job_id`, `dispatched_at` (KST). Move review ticket from `queue/` to `in-progress/`.
   - **Does not block.** Returns to the queue: pick up the next review ticket / poll prior pending jobs / track pattern_stuck state. Never sit idle waiting on a single codex call.
4. Result arrival — Roastmaster polls `/codex:result <codex_job_id>` on each turn (no inbox mediation; the codex job state lives in codex itself):
   - Fetch via `/codex:result <codex_job_id>`.
   - Translate codex findings into the report body (Korean), classify into BLOCKING / SHOULD / NIT / OUT-OF-SCOPE.
   - Set verdict: `APPROVE` / `COMMENT` / `BLOCKING`. Roastmaster may **downgrade** a codex BLOCKING to COMMENT when the finding is a legitimate trade-off (state why in the report), or **uphold** it. Never invent findings codex did not surface.
5. Move ticket to `done/`. Notify Technoking via inbox `kind: review_complete` with verdict.

When verdict differs from codex (downgrade / upgrade), Roastmaster briefly states why in the report's "Verdict 판정 사유" section.

### Non-blocking dispatch — invariants

- Roastmaster never `wait`/`sleep` on a codex job. The job runs on codex's side; Roastmaster checks back when its turn fires.
- Multiple PRs can be in-flight simultaneously: each has its own `RR-T-NNNN-<round>.md` placeholder while codex chews. Roastmaster processes them in arrival order.
- If codex result has not arrived after `codex_review_timeout` (default 30 min from `dispatched_at`), Roastmaster writes inbox `kind: escalation_needed`, `reason: codex_review_timeout`. Technoking decides (re-dispatch / halt).
- Pre-flight `/codex:status` still runs before each dispatch (no degraded mode).

## Auto-rescue triggers

Technoking dispatches `/codex:rescue --background` (no user approval) when **any** apply:

| Trigger | Detected by | Source |
|---|---|---|
| `error_2x` | Worker submits two `kind: error_2x` inbox messages with the same `error_signature` | Worker self-reports during build/test loops |
| `pattern_stuck` | Round-N review report has `pattern_stuck: true` | Roastmaster sets this when round-N BLOCKING repeats round-(N-1) BLOCKING in the same code area |

### Excluded — standard escalation instead

Inbox messages with `kind: escalation_needed` and one of these reasons **do not** auto-rescue:

- `requirements_change`
- `architectural_change`
- `untestable_ac`
- `codex_unavailable`

## `error_signature` calculation

```
error_signature = first 8 hex chars of SHA-1(<error_class>:<file>:<line>)
```

- `<error_class>`: error type or first non-whitespace stack-trace line (`NullPointerException`, `TypeError`, `compile_error`).
- `<file>`: repo-relative path of the file at fault.
- `<line>`: 1-based line number.

If file/line cannot be determined, use `<error_class>:unknown:0` — these always count as **distinct** signatures (they never trigger auto-rescue because the signature changes between attempts).

The worker computes the signature when emitting `kind: error_2x` and includes it in the inbox message. Technoking matches against the worker's previous `error_2x` for the same ticket.

## Rescue dispatch — the 6-step pipeline

```
0. Pre-flight                  /codex:status (halt if not ready)
1. Technoking dispatches       /codex:rescue --background, with the failing branch
                               name and a prompt body that includes the
                               error_signature for traceability. Codex plugin's
                               exact flags are owned by codex-plugin-cc; we pass
                               signature via prompt content, not as a flag.
                               → returns codex_job_id
2. Technoking writes record    .claude-team/rescues/RESCUE-<ts>.md (status: dispatched)
3. Continue other work         Technoking does not block — picks up next ticket
4. Patch arrives               Codex pushes a patch branch. If codex names it
                               differently, Technoking renames to rescue/T-NNNN
                               before spawning the validation ticket.
                               Detected on next /codex:status poll.
5. Spawn validation ticket     RV-NNNN with priority: top, assignee = original
                               ticket's worker. Worker merges rescue branch
                               locally, re-runs failing tests.
6. Re-review                   Roastmaster re-reviews on rescue branch (round resets).
                               APPROVE → merge. BLOCKING → see "validation failure".
```

Detailed schemas in `ticket-protocol` — `rescue` and `review` ticket types.

## Validation failure — never re-rescue

If validation fails (worker can't make tests pass with the patch, or Roastmaster BLOCKINGs the rescue):

- Mark `RESCUE-*` record `status: failed`.
- Worker emits `kind: escalation_needed`, `reason: rescue_failed`.
- Technoking pages user. **Do not auto-rescue a rescue.** At most one codex rescue per ticket per `error_signature`.

## Codex command invocation contract

Every codex invocation includes:

- `--background` for `/codex:rescue` (always).
- A clear scope reference (the PR branch, the ticket file path, the failing test name).
- The `error_signature` embedded in the rescue prompt body.

We **do not** assume codex command flags beyond what `codex-plugin-cc` documents. `/codex:setup` and `/codex:status` detect contract drift; if a flag breaks, surface via `kind: escalation_needed`, `reason: codex_unavailable` and let the user re-run `/codex:setup`.

## Cost and rate limits

Codex calls are billed against the user's OpenAI account. We do not throttle explicitly, but:

- Adversarial-review fires **once per review round** (not per file).
- Rescue fires **at most once per `error_signature` per ticket**.
- `/setup-team` may call `/codex:status` repeatedly (cheap status read).

To suspend codex calls (cost concern), the user pauses via `/abort` of in-flight tickets — not by editing this skill.

## Roastmaster's review report — codex section

Every review report must include a `Codex 리뷰 인용` section (see `ticket-protocol` review-report schema). Acceptable contents:

- Direct paste of `/codex:result` summary (preferred for short outputs).
- `codex_review_id: <id>` reference plus 1–3 line excerpt of the most material finding.
- "No findings" — explicitly stated, not omitted.

A review report missing this section is a procedure error and is rejected by Technoking as malformed.

## When this skill conflicts with the AC

The codex pipeline is a **system invariant**, not a per-ticket choice. AC cannot waive adversarial review. If an AC tries to (e.g., "skip codex for this trivial change"), Roastmaster files a procedural BLOCKING and Technoking reviews with the user — workflow change, not per-ticket exception.
