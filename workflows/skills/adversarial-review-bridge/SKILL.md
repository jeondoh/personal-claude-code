---
name: adversarial-review-bridge
description: Bridge between the workflows plugin and openai/codex-plugin-cc. Defines when and how to invoke /codex:adversarial-review and /codex:rescue, the auto-rescue triggers, error_signature calculation, and the rescue→validation→re-review pipeline. Use whenever Roastmaster reviews a PR, Technoking dispatches a rescue, or a worker validates a rescue patch.
---

# Adversarial Review Bridge

Single source of truth for integration with **openai/codex-plugin-cc** — a **hard dependency** verified by `/setup-team` before any ticket runs. If the codex plugin renames a command etc., update this file. Personas/skills consult this skill rather than embedding the codex contract.

## Codex commands we use

| Command | Owner | Purpose |
|---|---|---|
| `/codex:setup` | user (one-time) | Install codex CLI + authenticate |
| `/codex:status` | Technoking, scripts | Health check; by `/setup-team` and before each rescue dispatch |
| `/codex:adversarial-review` | Roastmaster | codex as adversarial reviewer on a PR/branch |
| `/codex:rescue` | Technoking | Background fix-it job for a stuck ticket |
| `/codex:result` | any persona | Retrieve output of a prior codex job by id |
| `/codex:cancel` | Technoking, `/abort` | Cancel an in-flight codex job |
| `/codex:review` | (unused) | We use the adversarial variant exclusively |

## Pre-flight — every codex call

Before any codex command the calling persona runs `/codex:status`. If not ready → write inbox `kind: escalation_needed`, `reason: codex_unavailable` and halt. No degraded mode.

## When Roastmaster invokes adversarial-review

**Every PR, every round.** No complexity-based skipping. **Codex is the sole reviewer** — Roastmaster never walks the diff itself; it dispatches, waits non-blockingly, then judges the codex result.

Step 9 of `/feat` (equivalent in `/task`):

1. Technoking opens PR.
2. Worker-review pane (Roastmaster) gets a review ticket.
3. Roastmaster — **non-blocking dispatch**:
   - `/codex:adversarial-review --background` against the PR branch. Capture `codex_job_id`.
   - Write placeholder `RR-T-NNNN-<round>.md` with `status: codex_pending`, `codex_job_id`, `dispatched_at` (KST). Move review ticket `queue/` → `in-progress/`.
   - **Does not block.** Return to queue: next review ticket / poll prior pending jobs / track pattern_stuck. Never idle on a single codex call.
4. Result arrival — Roastmaster polls `/codex:result <codex_job_id>` each turn (no inbox mediation; job state lives in codex):
   - Translate findings into the report body (Korean), classify into BLOCKING / SHOULD / NIT / OUT-OF-SCOPE.
   - Set verdict `APPROVE` / `COMMENT` / `BLOCKING`. May **downgrade** a codex BLOCKING to COMMENT for a legitimate trade-off (state why) or **uphold** it. Never invent findings codex did not surface.
5. Move ticket to `done/`. Notify Technoking via inbox `kind: review_complete` with verdict.

When verdict differs from codex (downgrade/upgrade), state why in the report's "Verdict 판정 사유" section.

### Non-blocking dispatch — invariants

- Never `wait`/`sleep` on a codex job. Roastmaster checks back when its turn fires.
- Multiple PRs in-flight simultaneously: each has its own `RR-T-NNNN-<round>.md` placeholder; processed in arrival order.
- If no result after `codex_review_timeout` (default 30 min from `dispatched_at`) → inbox `kind: escalation_needed`, `reason: codex_review_timeout`. Technoking decides (re-dispatch / halt).
- Pre-flight `/codex:status` still runs before each dispatch (no degraded mode).

## Auto-rescue triggers

Technoking dispatches `/codex:rescue --background` (no user approval) when **any** apply:

| Trigger | Detected by | Source |
|---|---|---|
| `error_2x` | Worker sends **one** `kind: error_2x` inbox message after self-detecting the same error twice; Technoking triggers immediately on receipt | Worker self-reports during build/test loops |
| `pattern_stuck` | Round-N review report has `pattern_stuck: true` | Roastmaster sets this when round-N BLOCKING repeats round-(N-1) BLOCKING in the same code area |

### Excluded — standard escalation instead

`kind: escalation_needed` with these reasons **do not** auto-rescue: `requirements_change`, `architectural_change`, `untestable_ac`, `codex_unavailable`.

## Findings classification

Roastmaster 가 codex review 결과를 4단계로 분류한다. Workflow gates depend on these labels — keep them consistent.

- **BLOCKING** — security flaw, correctness bug, contract violation, data corruption risk. Merge halted until resolved.
- **SHOULD** — design violation, maintainability concern, performance smell. Strongly recommended; may downgrade to COMMENT for a legitimate trade-off (state reason).
- **NIT** — style, naming, micro-optimization. Never blocks merge.
- **OUT-OF-SCOPE** — outside this PR's scope. Split into `BL-NNNN` backlog item, not addressed inline.

Verdict mapping: any BLOCKING → `BLOCKING`. SHOULDs/NITs alone → `COMMENT`. No findings → `APPROVE`.

## Error signature

```
error_signature = first 8 hex chars of SHA-1(<error_class>:<failing_component>)
```

- `<error_class>`: exception class or first non-whitespace stack-trace line (`NullPointerException`, `NoSuchBeanDefinitionException`, `TypeError`, `compile_error`).
- `<failing_component>`: failing bean name, test method name, or module — **NOT file:line** (file/line change on retry, breaking cross-attempt matching).
- Implementation: `printf '<error_class>:<failing_component>' | sha1sum | cut -c1-8`

Examples:
- `NoSuchBeanDefinitionException:ObjectMapper` → `a3f8b2e1`
- `NullPointerException:UserService.login` → `b4c91d3f`
- `TypeError:useAuthStore` → `c5da2e40`

If the failing component is undeterminable, use `<error_class>:unknown` — these are **distinct** signatures and never trigger auto-rescue (use time/attempt-based triggers; see worker personas).

The worker computes the signature after the second occurrence and includes it in the **single** `kind: error_2x` message. Technoking triggers rescue immediately on receiving any `kind: error_2x` — no second message required.

## Rescue dispatch pipeline

`error_2x` / `pattern_stuck` INBOX 수신 시 Technoking 이 실행하는 6단계. Pre-flight `/codex:status` 통과 가정 (실패 시 halt — see `Pre-flight`).

0. **De-dup check** — same `source_ticket` + same `error_signature` already has a `.claude-team/rescues/RESCUE-*.md`? → escalate to user, no new dispatch. At most one rescue per ticket per `error_signature`.
1. **알림 파싱** — `INBOX-<ts>-<pane>.json` 에서 `kind`, `error_signature`, `rev_count`, `source_ticket` 추출.
2. **추적 파일 생성** — `.claude-team/rescues/RESCUE-<ts>-<ticket>.md` (`source_ticket`, `error_signature`, `dispatched_at`, `status: dispatched`).
3. **codex 호출** — `/codex:rescue --background` 비차단 디스패치. `error_signature` 는 prompt body 에 포함 (codex-plugin-cc flag 가정 X). → returns `codex_job_id`. 즉시 다음 작업으로 복귀.
4. **검증 ticket 발행** — codex 가 패치 브랜치를 push 하면 (감지: 다음 `/codex:status` poll), `RV-NNNN-<slug>.md` 생성. Schema: `type: review`, sub-case 4b, `priority: top`, `assignee` = 원 ticket worker, header field `rescue_branch: rescue/T-{NNNN}`. 브랜치명이 다르면 `rescue/T-{NNNN}` 으로 rename 후 발행.
5. **결과 처리** — RV ticket PASS → 머지 게이트 (Roastmaster 재리뷰). FAIL → `RESCUE-*` `status: failed`, 사용자 에스컬레이션. Rescue 재시도 없음 (see `Validation failure — never re-rescue`).

Detailed schemas in `ticket-protocol § Ticket type schemas` (`rescue`, `review § 4b`) and `Rescue validation cycle`.

## codex-plugin-cc 계약 가정 (rescue 파이프라인 의존)

| 가정 | 위반 시 증상 |
|---|---|
| `/codex:rescue --background` 가 background job 으로 큐잉되고 `codex_job_id` 반환 | foreground block — Technoking idle 잠김 |
| `/codex:result <job_id>` 가 patch diff 또는 branch 명 반환 | patch 수령 불가 |
| codex 가 패치를 (1) 브랜치로 푸시 OR (2) diff 텍스트로 반환 | rescue 완료 감지 실패 |

위반 발견 시: Technoking 이 `kind: escalation_needed`, `reason: codex_unavailable` 발사 → 사용자에게 codex-plugin-cc 버전 확인 안내 → 자동 재시도 X (degraded mode 없음).

## Validation failure — never re-rescue

If validation fails (worker can't make tests pass with the patch, or Roastmaster BLOCKINGs the rescue):

- Mark `RESCUE-*` record `status: failed`.
- Worker emits `kind: escalation_needed`, `reason: rescue_failed`.
- Technoking pages user. **Do not auto-rescue a rescue.** At most one codex rescue per ticket per `error_signature`.

## Codex command invocation contract

Every codex invocation includes:

- `--background` for `/codex:rescue` (always).
- A clear scope reference (PR branch, ticket file path, failing test name).
- The `error_signature` embedded in the rescue prompt body.

We **do not** assume codex flags beyond what `codex-plugin-cc` documents. `/codex:setup` and `/codex:status` detect contract drift; if a flag breaks, surface via `kind: escalation_needed`, `reason: codex_unavailable` and let the user re-run `/codex:setup`.

## Cost and rate limits

Codex calls bill the user's OpenAI account. We do not throttle explicitly, but:

- Adversarial-review fires **once per review round** (not per file).
- Rescue fires **at most once per `error_signature` per ticket**.
- `/setup-team` may call `/codex:status` repeatedly (cheap status read).

To suspend codex calls (cost), the user pauses via `/abort` of in-flight tickets — not by editing this skill.

## Roastmaster's review report — codex section

Every review report must include a `Codex 리뷰 인용` section (see `ticket-protocol` review-report schema). Acceptable contents:

- Direct paste of `/codex:result` summary (preferred for short outputs).
- `codex_review_id: <id>` reference plus 1–3 line excerpt of the most material finding.
- "No findings" — explicitly stated, not omitted.

A report missing this section is a procedure error and is rejected by Technoking as malformed.

## When this skill conflicts with the AC

The codex pipeline is a **system invariant**, not a per-ticket choice. AC cannot waive adversarial review. If an AC tries to (e.g., "skip codex for this trivial change"), Roastmaster files a procedural BLOCKING and Technoking reviews with the user — workflow change, not per-ticket exception.
