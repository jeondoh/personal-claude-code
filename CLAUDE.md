# personal-claude-code — 글로벌 가이드

이 마켓플레이스는 **회사처럼 굴러가는 7명 팀** 으로 Claude Code 를 운영하기 위한 개인용 플러그인 묶음이다. Technoking 이 사용자 요청을 받으면 복잡도를 판정하고 (small/medium/large), 적절한 페르소나에게 작업을 분배하며, tmux 페인에서 헤드리스 `claude` 인스턴스로 병렬 처리한다. 모든 PR 은 `/codex:adversarial-review` 를 통과해야 머지된다 — Roastmaster 가 비차단으로 dispatch 하고, codex 결과 도착 시 verdict 를 판정·정리한다 (자체 diff 워크 없음).

## 7명의 팀

| # | 이름 | 직책 | 모델 | 페인 |ㄱ
|---|---|---|---|---|
| 1 | **Technoking** | Tech Lead — 라이프사이클 마스터, ticket 분배, rescue 디스패치 | **opus** | `main` |
| 2 | **Spec Shaman** | Product Owner — PRD 작성 (사용자 산출물, 한국어) | sonnet | subagent |
| 3 | **Galaxy Brain** | System Architect — Design Doc·ADR·인터페이스 설계 | **opus** | subagent |
| 4 | **Persistence Paladin** | Backend — Kotlin/Spring, DB, 보안 흡수 | sonnet | `worker-be` |
| 5 | **Pixel Wizard** | Frontend — Next.js, 디자인·a11y 흡수 | sonnet | `worker-fe` |
| 6 | **What-If Witch** | QA — 인수 테스트 선행, 통합·E2E 검증 | sonnet | `worker-qa` |
| 7 | **The Roastmaster** | Code Reviewer — codex 비차단 dispatch + verdict 판정 + pattern_stuck 추적 (자체 diff 워크 X) | **opus** | `worker-review` |

## 핵심 컨벤션 (한 줄에 하나)

| 항목 | 규칙 |
|---|---|
| 본문 언어 — 사용자 산출물 | **한국어** (PRD, Design Doc, ADR, Diagnose, Handoff, Review report, **commit subject·body, PR title·body, codex review 결과 요약**). 사용자가 직접 읽음. |
| 본문 언어 — 그 외 | 영어 (페르소나 본문, 스킬, 워커 ticket, inbox JSON, 코드, 커맨드, conventional commits `<type>(<scope>):` prefix, footer keys `Refs:`/`Closes:`/`Co-Authored-By:`). 압축 우선. |
| YAML frontmatter | 영어 keys/enums (프로그램틱 파싱). |
| 타임스탬프 | KST (UTC+9), ISO 8601 with `+09:00`. Date-only `YYYY-MM-DD`. |
| Ticket ID | 4자리 zero-pad: `T-0042`, `RV-0007`, `BL-0019`. 9999 초과 시 5자리 자동 확장. |
| 카운터 | `.claude-team/workers/registry.json` 의 `counters: {T, RV, BL}`. RESCUE/HANDOFF 는 timestamp. |
| codex 의존성 | **HARD**. `/codex:status` 통과 못하면 어떤 ticket 도 진행 불가. soft/degraded 모드 없음. |
| Technoking wake | `fswatch` + 40s watchdog 데몬 (`technoking-daemons.sh`, `/setup-team` 가 launch). Inbox 이벤트 → `wake.log` → Technoking 의 `Monitor("tail -F")` 구독. 폴링 / `tmux send-keys` 없음. `brew install fswatch` 필요. |
| 품질 게이트 | complexity (small/medium/large) **무관 전체** 적용 — codex 어드버서리얼 리뷰 (Roastmaster 가 비차단 dispatch·verdict 판정) + 자동 rescue. 자체 코드 리뷰 없음. |
| 자동 rescue 트리거 | 워커 같은 에러 2회 (`error_2x`) / Roastmaster `pattern_stuck: true`. 사용자 승인 없이 발동. |
| Stop 정책 (B 패턴) | small=0 / medium=1 (PRD+Design 통합) / large=3 (PRD·Design·batch). 머지 직전 Stop 없음. |
| 추적 / gitignore | 추적 = `docs/*` (PRD/Design/ADR/Diagnose). gitignore = `.claude-team/`, `.worktrees/`. |

## 디렉터리 (`.claude-team/`)

```
tickets/queue/        ← Technoking 발행
tickets/in-progress/  ← 워커 작업 중
tickets/done/         ← 완료 (영구 보존 — archive·삭제 X)
tickets/cancelled/    ← 취소 (auto-archive 7d)
reviews/              ← Roastmaster 보고서 (RR-T-NNNN-N.md)
inbox/                ← 워커→Technoking 알림
rescues/              ← codex-rescue 추적
backlog/              ← OUT-OF-SCOPE (BL-NNNN-*.md)
handoff/              ← /handoff 직렬화
archive/{YYYY-MM}/    ← /cleanup 또는 자동 트리거 이동
workers/registry.json ← pane↔persona↔PID + counters
config.yml            ← /setup-team 출력 (codex verified_at 등)
```

## 스킬 구성 맵 (질문 → 스킬)

| 질문 | 스킬 |
|---|---|
| 라이프사이클·복잡도 판정·Stop 정책·escalation | `orchestration-guide` |
| ticket 파일 schema, 디렉터리, archive | `ticket-protocol` |
| 페인 메시지 전달 (파일 기반) | `tmux-worker-protocol` |
| codex 호출, 리뷰, rescue 파이프라인 | `adversarial-review-bridge` |
| 브랜치명·커밋·PR·worktree | `git-flow` |
| PRD / Design / ADR / Diagnose 본문 규약 | `documentation-criteria` |
| 코드 품질 (스택 무관) | `coding-principles` |
| 테스트 규칙 (스택 무관) | `testing-principles` |
| Kotlin/Spring 스택 | `stacks/kotlin-spring/skills/*` (kotlin-spring-boot-core, data-access, testing-kotlin) |
| Next.js 스택 | `stacks/nextjs/skills/*` (nextjs-core, frontend-data, testing-nextjs) |

## 슬래시 커맨드 12개

| 카테고리 | 커맨드 |
|---|---|
| 라이프사이클 | `/feat` (전체 11단계), `/design` (PRD·Design 만), `/task` (small 3-step), `/review` (PR 재리뷰) |
| 진단·운영 | `/diagnose` (조사·제안), `/setup-team` (셋업), `/status` (보드), `/abort` (취소) |
| 직렬화·확장 | `/handoff` (컨텍스트 직렬화), `/hire` (페르소나 추가), `/show-team` (로스터), `/cleanup` (archive) |

## 이 마켓을 쓰는 동안 Claude 가 잊지 말 것

1. **사용자 산출물은 한국어, 그 외는 영어**. PRD body 를 영어로, 페르소나 본문을 한국어로 쓰지 말 것.
2. **codex 가 죽어 있으면 어떤 ticket 도 진행 X**. `/codex:status` 가 ready 가 아니면 즉시 halt + `/codex:setup` 안내.
3. **품질 게이트는 small 도 강제**. `/task` 도 codex 어드버서리얼 리뷰 (Roastmaster 가 dispatch·verdict) + rescue 게이트가 동일 적용된다. 자체 diff 리뷰는 어떤 경로에서도 수행하지 않음.
4. **커맨드 본문에 직접 로직 박지 말 것**. 항상 SKILL 위임 (`see orchestration-guide`, `see ticket-protocol`).
5. **압축 우선**. 페르소나·스킬·커맨드 본문은 핵심만. 부가 설명·중복 표현 제거.
6. **새 추상화 도입 금지**. 기존 SKILL/페르소나/커맨드/디렉터리 외에 임의로 카테고리·계층 추가 X. 필요하면 사용자에게 묻기.
7. **자동 rescue 는 사용자 승인 없음**. `error_2x` / `pattern_stuck` 만 트리거. 그 외 (`requirements_change`, `architectural_change`, `untestable_ac`) 는 표준 escalation.
8. **머지 직전 Stop 없음**. medium=step 5 / large=step 6 batch 승인 후에는 step 11 머지까지 자율. 사용자가 인터럽트 가능.
9. **review report 접두사는 `RR-T-NNNN-<round>.md`** (rescue validation ticket 은 `RV-NNNN`, 둘은 다른 것).
10. **본문이 가이드 분량 살짝 초과해도 net 증가 인정** — 필수 컨텐츠 (Versions 박스, canonical commands, BLOCKING 항목) 가 압축분을 초과하면 그대로.
11. **codex 호출은 비차단 (`--background`)**. Roastmaster 는 dispatch 후 즉시 다음 리뷰 / 폴링 / pattern_stuck 추적으로 복귀. 단일 codex job 을 기다리며 idle 상태 유지 금지.

## 추가 참조

- 마켓플레이스 설치: `/plugin marketplace add sideholic/personal-claude-code` 후 `workflows@personal-claude-code` (필수) + 스택 플러그인 (옵션).
- 첫 실행 흐름: `/codex:setup` (codex CLI 인증) → `/setup-team` (tmux + .claude-team) → `/feat <request>`.
- 사용자 문서: `docs/installation.md`, `docs/personas.md`, `docs/ticket-protocol.md`, `docs/tmux-layout.md`, `docs/git-flow.md`.

이 파일은 globally pinned. 페르소나·스킬·커맨드 어디서든 충돌이 생기면 이 파일의 정책이 우선한다.
