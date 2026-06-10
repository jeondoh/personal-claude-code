# 페르소나 — 7명의 팀

이 마켓플레이스는 **회사처럼 굴러가는 7명** 으로 구성된다. 각 페르소나는 모델, 페인, 책임 영역이 명확히 구분되며, Technoking 이 전체 라이프사이클을 조율한다.

`/show-team` 의 출력은 이 문서의 표와 일치한다.

## 한눈에

| # | 이름 | 직책 | 모델 | 페인 |
|---|---|---|---|---|
| 1 | **Technoking** | Tech Lead | **opus** | `main` |
| 2 | **Spec Shaman** | Product Owner | sonnet | subagent |
| 3 | **Galaxy Brain** | System Architect | **opus** | subagent |
| 4 | **Persistence Paladin** | Backend | **opus** (effort: medium) | `worker-be` |
| 5 | **Pixel Wizard** | Frontend | **opus** (effort: medium) | `worker-fe` |
| 6 | **What-If Witch** | QA | sonnet | `worker-qa` |
| 7 | **The Roastmaster** | Code Reviewer (codex dispatcher·judge) | **opus** | `worker-review` |

opus 다섯 명 — Technoking·Galaxy Brain·Roastmaster (무겁고 cross-cutting 한 결정) + Persistence Paladin·Pixel Wizard (구현 품질 우선, 페르소나 frontmatter 의 `effort: medium` 으로 발화). sonnet 두 명 — Spec Shaman·What-If Witch (단일 책임 + 빠른 회전).

## 1. Technoking — Tech Lead

라이프사이클 마스터. 사용자 요청을 받으면 복잡도 (small/medium/large) 를 판정하고 `/feat` 11단계를 진행한다. ticket 발행, 워커 디스패치, Roastmaster 리뷰 트리거, 자동 rescue 결정, 머지까지 책임.

**Stop 정책 (B 패턴)**: small=0, medium=1 (PRD+Design 통합), large=3 (PRD·Design·batch). 머지 직전 Stop 없음.

**모델 = opus**: 전체 라이프사이클·다중 워커 상태·inbox 알림·rescue 진행 상황을 동시 시야로 추적해야 한다. 세션이 길어질수록 컨텍스트 부담이 커지므로 1M 컨텍스트.

**첫 실행 루틴**: 새 세션 첫 호출 시 `.claude-team/` 상태 (진행 ticket·대기 ticket·미처리 inbox·in-flight rescue·최신 handoff·git 상태) 를 read-only 로 스캔하고, 한국어로 상태·즉시 처리 항목·다음 진행거리 1~3개를 보고한 뒤 사용자 액션을 기다린다. 보고 전까지 새 dispatch 금지. 자세한 절차는 `workflows/agents/technoking.md § Initial Run Routine`.

**소속 페인**: `main` — 사용자가 attach 시 직접 보는 자리. Technoking 은 사용자와 직접 대화하며 Stop 승인을 받는다.

## 2. Spec Shaman — Product Owner

PRD 작성 전담. 사용자 요청을 인수 기준 (AC) 으로 분해하고, 비즈니스 룰·엣지 케이스·예외 흐름을 한국어로 명료하게 정리한다.

**산출물**: `docs/prd/<slug>-prd.md`. body 한국어, frontmatter 영어.

**페인**: subagent only. tmux 페인 없음 — Technoking 가 `Task()` 로 일회성 호출.

## 3. Galaxy Brain — System Architect

Design Doc + ADR + 인터페이스 설계. PRD 받아서 컴포넌트 분할, 데이터 모델, API 시그니처, 외부 의존성, 마이그레이션 전략을 도출한다. ADR 트리거는 `documentation-criteria` 스킬 참조.

**산출물**: `docs/design/<slug>-design.md`, 필요 시 `docs/adr/ADR-NNNN-*.md`. body 한국어.

**모델 = opus**: 시스템 전반을 동시에 시야에 두고 트레이드오프를 따져야 하므로 1M 컨텍스트.

**페인**: subagent only.

## 4. Persistence Paladin — Backend

Kotlin + Spring Boot 작업. DB 스키마, 트랜잭션, 보안 (authN/authZ) 영역도 흡수. 스택 핀: JDK 24 / Kotlin 2.2.21 / Spring Boot 4.0.6 / Gradle Kotlin DSL.

**핵심 룰**: JPA entity 는 `data class` 금지, 수동 `open`/`no-arg` 금지 (`allOpen` 플러그인이 처리), Coroutine + `@Transactional` 컨텍스트 누수 footgun, Flyway `outOfOrder=false` BLOCKING.

**페인**: `worker-be`.

## 5. Pixel Wizard — Frontend

Next.js + React 작업. 디자인·접근성 (a11y) 영역도 흡수. 스택 핀: Next.js 15 / React 19 / Node ≥20.11 / TS 5 / pnpm 9 / TanStack Query v5+ / MSW v2+.

**핵심 룰**: Server Action authN ≠ authZ 분리, `useTransition` 적절히 사용, SSR HydrationBoundary 패턴, MSW v2 의 새 핸들러 시그니처.

**페인**: `worker-fe`.

## 6. What-If Witch — QA

인수 테스트 선행 (fail-first) 작성 + 통합·E2E 검증. PRD 의 AC 한 개당 테스트 한 개. 테스트가 빨강일 때 워커가 구현을 시작한다 (TDD-ish).

**escalation**: AC 가 테스트로 표현 불가능하면 `escalation_needed: untestable_ac` → 사용자 호출.

**페인**: `worker-qa`.

## 7. The Roastmaster — Code Reviewer

Final boss. **자체 diff 워크 없음** — codex 가 단독 reviewer. PR 마다 `/codex:adversarial-review --background` 비차단 dispatch → placeholder `RR-T-NNNN-<round>.md` (`status: codex_pending`) 작성 → 즉시 큐로 복귀 (다른 리뷰·폴링·pattern_stuck 추적). 다음 턴에 codex 결과 도착 시 한국어 본문으로 정리 + verdict 판정 (uphold / downgrade / escalate). verdict: `APPROVE | COMMENT | BLOCKING`.

**주요 역할 5가지**:
1. codex 비차단 dispatch (`--background`).
2. 결과 도착 시 한국어 RR 보고서 작성 + BLOCKING/SHOULD/NIT/OUT-OF-SCOPE 분류.
3. verdict 판정 — codex 결과 채택 또는 trade-off 인정 시 강등.
4. pattern_stuck 추적 (같은 영역 BLOCKING 2라운드 반복) → Technoking 에 inbox 신호.
5. 리뷰 라운드 관리 (max 3 BLOCKING), 워커 escalation 첫 수신.

**자동 rescue 트리거**: `pattern_stuck: true` → Technoking 가 `/codex:rescue --background`. Roastmaster 직접 rescue 호출 금지.

**모델 = opus**: codex 결과 + 사전 컨벤션 + 라운드 히스토리 + trade-off 판정을 동시 시야로 처리하기 위함. 단순 디스패처 이상.

**페인**: `worker-review`.

## 페르소나 추가 (`/hire`)

기본 7명으로 부족하면 `/hire <slug>` 로 신규 페르소나 추가 가능. 새 페르소나 파일은 `workflows/agents/<slug>.md` 에 생성되며 `workers/registry.json` 의 panes 또는 subagents 섹션이 갱신된다. 기본 7명은 reserved — 같은 슬러그로 덮어쓸 수 없다.

## 더 알아보기

- 라이프사이클 흐름: `CLAUDE.md` § 7명의 팀 / `workflows/skills/orchestration-guide/SKILL.md`
- 각 페르소나 본문 (영어, 자세한 mandate / inputs / outputs): `workflows/agents/<slug>.md`
- 리뷰 + codex 통합: `workflows/skills/adversarial-review-bridge/SKILL.md`
