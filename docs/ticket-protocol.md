# Ticket Protocol — 사용자 가이드

`.claude-team/` 디렉터리 안의 파일들이 무엇을 의미하는지, 언제 수동으로 개입할 수 있는지 설명합니다.

---

## 이 문서를 언제 보나

- `/status` 출력이 부족하고, ticket 파일을 직접 확인하고 싶을 때
- 워커가 멈춘 것 같거나, rescue 가 돌고 있는데 진행이 없을 때
- 특정 ticket 을 취소·재배정·우선순위 변경하고 싶을 때

---

## 디렉터리 한눈에

```
.claude-team/
├── tickets/
│   ├── queue/          # 발행됨, 아직 워커가 가져가지 않은 ticket
│   ├── in-progress/    # 워커가 작업 중 (in_review 상태도 여기 있음)
│   ├── done/           # 머지 완료 (30일 후 archive)
│   └── cancelled/      # 취소됨 (7일 후 archive)
├── reviews/            # Roastmaster 리뷰 보고서 (RR-T-*.md)
├── inbox/              # 워커 ↔ Technoking 알림 (처리 후 삭제)
├── rescues/            # codex rescue 추적 레코드
├── backlog/            # out-of-scope 항목 (BL-NNNN-*.md)
├── handoff/            # /handoff 직렬화 결과
├── archive/{YYYY-MM}/  # /cleanup 이동 대상 (읽기 전용)
├── workers/
│   └── registry.json   # 페인 ↔ 페르소나 ↔ PID + 카운터
└── config.yml          # /setup-team 이 작성 (codex 인증 시각 등)
```

---

## Ticket ID 의미

| 접두사 | 의미 | 예 |
|---|---|---|
| `T-NNNN` | 일반 작업 ticket | `T-0042` |
| `RV-NNNN` | Rescue 검증 ticket (codex 패치 도착 후 자동 생성) | `RV-0007` |
| `RR-T-NNNN-N` | Roastmaster 리뷰 보고서 (N = 리뷰 라운드) | `RR-T-0042-1` |
| `BL-NNNN` | 백로그 (작업 중 발견된 out-of-scope 항목) | `BL-0019` |
| `RESCUE-<ts>` | codex rescue 디스패치 레코드 | `RESCUE-20260511T143000+0900` |
| `HANDOFF-<ts>` | `/handoff` 컨텍스트 직렬화 | `HANDOFF-20260511T180000+0900` |
| `INBOX-<ts>-<pane>` | 워커 → Technoking (또는 역방향) 알림 | `INBOX-...-worker-be` |

숫자 카운터는 4자리 zero-pad (`T-0001`). 9999 초과 시 5자리로 자동 확장. `RR-`, `RESCUE-`, `HANDOFF-`, `INBOX-` 는 타임스탬프 기반이며 카운터 소비 없음.

---

## Ticket 상태 흐름

```
[queue] → [in_progress] → [in_review] → [done]
                ↘
            [cancelled]  (언제든 /abort 로)
```

| 전이 | 주체 | 위치 변화 |
|---|---|---|
| `queued → in_progress` | 워커 | `queue/` → `in-progress/` |
| `in_progress → in_review` | 워커 완료 신호 → Technoking PR 생성 | 파일은 `in-progress/` 유지, status 필드만 변경 |
| `in_review → done` | PR 머지 후 Technoking | `in-progress/` → `done/` |
| `* → cancelled` | `/abort` 또는 Technoking 강제 취소 | `in-progress/` 또는 `queue/` → `cancelled/` |

Rescue 흐름: `dispatched → patch_received → validation_queued → resolved` (또는 `failed` → 사용자 escalation).

---

## 리뷰 라운드에서 보이는 파일

PR 한 개에 review round 가 1·2·3 으로 진행될 수 있다. 매 round 마다 다음이 새로 생긴다:

| round 시점 | 파일 | 위치 |
|---|---|---|
| Technoking 가 라운드 시작 | `RV-NNNN-<slug>.md` (`type: review`, `round: N`) | `tickets/queue/` |
| Roastmaster pickup | 같은 파일 | `tickets/in-progress/` |
| Roastmaster placeholder | `RR-T-NNNN-N.md` (`status: codex_pending`) | `reviews/` |
| codex 결과 도착 후 finalize | 같은 placeholder 파일 갱신 (`status: review-done`, `verdict`) | `reviews/` |

verdict (`APPROVE | COMMENT | BLOCKING`) 후:

- **APPROVE** → step 10 (Integration + E2E, large 기본 / medium=AC 따라) → step 11 머지
- **COMMENT** → 머지 진행 가능. 워커가 inline 수정은 같은 브랜치에 push (새 round 트리거 X). 큰 follow-up 은 `BL-NNNN` 백로그. COMMENT 격상 필요 시 워커가 `kind: needs_reblock` inbox 발행 → Technoking 가 BLOCKING 처리.
- **BLOCKING** → 워커 fix → push → `kind: fix_pushed` inbox → Technoking 가 round+1 의 `RV-NNNN` 새 ticket 발행. 최대 3 round. round 3 BLOCKING 이면 사용자 escalation.

---

## Ticket 파일 구조

모든 ticket 은 YAML frontmatter + 마크다운 body.

```yaml
---
id: T-0042                           # Ticket ID
type: work                           # work | review | review-report | rescue | backlog | handoff | inbox
title: idempotency key on charge     # kebab-slug 파일명에도 반영
status: queued                       # 현재 상태 (위 흐름 참고)
author: technoking                   # 발행 페르소나 slug
assignee: worker-be                  # 담당 페인 slug (unassigned 가능)
complexity: small | medium | large
parent_feature: feat/T-0040-...      # 상위 /feat ticket (있으면)
acceptance_criteria: [AC-001]
files_in_scope:
  - apps/api/src/payments/charge.kt
depends_on: [T-0041]                 # 이 ticket 이 먼저 머지되어야 함
created: 2026-05-11T14:30:00+09:00   # KST ISO-8601
updated: 2026-05-11T14:30:00+09:00
---
```

**body 언어 정책**: Work ticket body 는 영어 (페르소나용). PRD / Design Doc / Diagnose / Handoff body 는 한국어 (사용자 산출물).

---

## 수동 개입 시나리오

**ticket 취소** — 가장 안전한 방법:
```
/abort T-0042
```
워커에 abort 지시 → worktree 회수 → `cancelled/` 이동 자동 처리.

**assignee 변경** — Technoking 에 알리는 방식:
1. `tickets/in-progress/T-0042-*.md` 의 `assignee` 필드 직접 수정 후 `updated` 갱신.
2. inbox 파일 수동 작성으로 Technoking 에 지시 (`kind: directive`).

**우선순위 조정** — queue 순서 바꾸기:
- frontmatter 에 `priority: top | high | medium | low` 추가 (Technoking 이 폴링 시 참고).
- 또는 `created` 타임스탬프를 앞당겨 정렬 순서 조작 (단순 우회).

**rescue 무한 반복 중단**:
1. 해당 rescue 레코드(`rescues/RESCUE-*.md`)에서 상태 확인.
2. 원인 ticket 에 inbox `kind: escalation_needed` + `reason: rescue_failed` 메시지 작성.
3. Technoking 이 다음 폴링 시 halt 하고 사용자 호출.

**inbox `kind` 빠른 참고**:

| kind | 방향 | 의미 |
|---|---|---|
| `progress` | 워커 → Technoking | 진행 상황 알림 (비차단) |
| `completion` | 워커 → Technoking | 브랜치 푸시 완료, PR 준비됨 |
| `directive` | Technoking → 워커 | mid-ticket pivot·abort·refocus |
| `error_2x` | 워커 → Technoking | 같은 에러 2회 → auto-rescue 트리거 |
| `pattern_question` | 워커 → Technoking | 비차단 질문 |
| `review_complete` | worker-review → Technoking | verdict 발행 (APPROVE/COMMENT/BLOCKING) |
| `pattern_stuck` | worker-review → Technoking | 같은 BLOCKING 2라운드 → auto-rescue |
| `fix_pushed` | 워커 → Technoking | BLOCKING 후 fix 푸시 완료 |
| `needs_reblock` | 워커 → Technoking | COMMENT → BLOCKING 격상 요청 |
| `escalation_needed` | 누구나 → Technoking | reason 필드로 사유 명시 (`rescue_failed`, `untestable_ac`, `codex_review_timeout` 등) |
| `review_request` | Technoking → worker-review | ad-hoc 리뷰 요청 (큐 ticket 발행이 표준; 이 채널은 예외용) |

---

## Archive 정책

| 대상 | 보존 기간 | 이동 위치 |
|---|---|---|
| `done/` ticket | 30일 후 | `archive/{YYYY-MM}/` |
| `cancelled/` ticket | 7일 후 | `archive/{YYYY-MM}/` |
| `reviews/` 리뷰 보고서 | 머지 30일 후 | `archive/{YYYY-MM}/` |
| `rescues/` 레코드 | 30일 후 | `archive/{YYYY-MM}/` |

즉시 실행: `/cleanup` 커맨드. archive 파일은 읽기 전용으로 보존됨.

---

## `.claude-team/` 은 gitignore

`.claude-team/` 과 `.worktrees/` 는 repo 추적 대상이 아닙니다. 사용자가 직접 백업이 필요하면 `tar czf claude-team-backup.tar.gz .claude-team/` 으로 수동 압축 보관하세요. 팀 공유 필요 시 별도 저장소 또는 공유 드라이브 활용.
