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
| `error_2x` | Worker sends **one** `kind: error_2x` inbox message after self-detecting the same error twice. Technoking triggers rescue immediately on receiving it. | Worker self-reports during build/test loops |
| `pattern_stuck` | Round-N review report has `pattern_stuck: true` | Roastmaster sets this when round-N BLOCKING repeats round-(N-1) BLOCKING in the same code area |

### Excluded — standard escalation instead

Inbox messages with `kind: escalation_needed` and one of these reasons **do not** auto-rescue:

- `requirements_change`
- `architectural_change`
- `untestable_ac`
- `codex_unavailable`

## Findings classification

Roastmaster 가 codex review 결과를 4단계로 분류한다. Workflow gates depend on these labels — keep them consistent.

- **BLOCKING** — security flaw, correctness bug, contract violation, data corruption risk. Merge halted until resolved.
- **SHOULD** — design violation, maintainability concern, performance smell. Strongly recommended; may downgrade to COMMENT when a legitimate trade-off exists (state reason in report).
- **NIT** — style, naming, micro-optimization. Never blocks merge.
- **OUT-OF-SCOPE** — outside this PR's scope. Split off into `BL-NNNN` backlog item, not addressed inline.

Verdict mapping: any BLOCKING → verdict `BLOCKING`. SHOULDs and NITs alone → `COMMENT`. No findings → `APPROVE`.

## Error signature

```
error_signature = first 8 hex chars of SHA-1(<error_class>:<failing_component>)
```

- `<error_class>`: exception class or first non-whitespace stack-trace line (`NullPointerException`, `NoSuchBeanDefinitionException`, `TypeError`, `compile_error`).
- `<failing_component>`: the bean name, test method name, or module that consistently fails — **NOT file:line**. File and line numbers change when the worker retries, which breaks matching across attempts.
- Implementation: `printf '<error_class>:<failing_component>' | sha1sum | cut -c1-8`

Examples:
- `NoSuchBeanDefinitionException:ObjectMapper` → `a3f8b2e1`
- `NullPointerException:UserService.login` → `b4c91d3f`
- `TypeError:useAuthStore` → `c5da2e40`

If the failing component cannot be determined, use `<error_class>:unknown` — these count as **distinct** signatures and never trigger auto-rescue (use time/attempt-based triggers instead; see worker personas).

The worker computes the signature after the second occurrence and includes it in the **single** `kind: error_2x` inbox message. Technoking triggers rescue immediately on receiving any `kind: error_2x` message — no second message required.

## Rescue dispatch pipeline

`error_2x` / `pattern_stuck` INBOX 수신 시 Technoking 이 실행하는 6단계. Pre-flight `/codex:status` 통과 가정 (실패 시 halt — see `Pre-flight`).

0. **De-dup check** — same `source_ticket` + same `error_signature` already has a `.claude-team/rescues/RESCUE-*.md`? → escalate to user, no new dispatch. At most one rescue per ticket per `error_signature`.
1. **알림 파싱** — `INBOX-<ts>-<pane>.json` 에서 `kind`, `error_signature`, `rev_count`, `source_ticket` 추출.
2. **추적 파일 생성** — `.claude-team/rescues/RESCUE-<ts>-<ticket>.md` 작성 (`source_ticket`, `error_signature`, `dispatched_at`, `status: dispatched`).
3. **codex 호출** — `/codex:rescue --background` 비차단 디스패치. `error_signature` 는 prompt body 에 포함 (codex-plugin-cc 의 flag 는 가정하지 않음). → returns `codex_job_id`. Technoking 은 즉시 다음 작업으로 복귀.
4. **검증 ticket 발행** — codex 가 패치 브랜치를 push 하면 (감지: 다음 `/codex:status` poll), `RV-NNNN-<slug>.md` 생성. Schema: `type: review`, sub-case 4b, `priority: top`, `assignee` = 원 ticket worker, header field `rescue_branch: rescue/T-{NNNN}`. 브랜치명이 다르면 Technoking 이 `rescue/T-{NNNN}` 으로 rename 후 발행.
5. **결과 처리** — RV ticket 검증 PASS → 머지 게이트 (Roastmaster 재리뷰). FAIL → `RESCUE-*` `status: failed`, 사용자 에스컬레이션. Rescue 재시도 없음 (see `Validation failure — never re-rescue`).

Detailed schemas in `ticket-protocol § Ticket type schemas` (`rescue`, `review § 4b`) and `Rescue validation cycle`.

## codex-plugin-cc 계약 가정 (rescue 파이프라인 의존)

이 파이프라인은 codex-plugin-cc 의 다음 동작을 가정한다:

| 가정 | 위반 시 증상 |
|---|---|
| `/codex:rescue --background` 가 background job 으로 큐잉되고 `codex_job_id` 반환 | foreground block — Technoking idle 잠김 |
| `/codex:result <job_id>` 가 patch diff 또는 branch 명 반환 | patch 수령 불가 |
| codex 가 패치를 (1) 브랜치로 푸시 OR (2) diff 텍스트로 반환 | rescue 완료 감지 실패 |

위반 발견 시:
- Technoking 은 `kind: escalation_needed`, `reason: codex_unavailable` 발사
- 사용자에게 codex-plugin-cc 버전 확인 안내
- 자동 재시도 X — degraded mode 없음

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
