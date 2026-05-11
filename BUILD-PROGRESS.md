# Build Progress — `sideholic/personal-claude-code`

> 목적: 이 파일만 읽으면 다음 세션에서 작업 이어갈 수 있도록.
> 작성: 2026-05-10 (초안) · 갱신: 2026-05-11 (A 단계 review/fix 완료, 컨텍스트 초기화 전 핸드오프). KST.

---

## 다음 세션 시작 방법 (자율주행 모드)

**사용자 결정 (2026-05-11)**: 5~8단계 자율 진행. pane 2 가 분배·취합·압축까지 책임. 컨텍스트 가득 차면 문서 갱신·초기화·재진입 반복.

1. 새 Claude Code 세션 시작 (pane 2 = opus 권장 — 마스터 오케스트레이터)
2. 첫 메시지 (사용자가 입력):
   > "BUILD-PROGRESS.md 와 AUTONOMOUS-PLAN.md 읽고 자율주행 시작. 5단계부터."
   중도 재개 시:
   > "BUILD-PROGRESS.md 와 AUTONOMOUS-PLAN.md 읽고 자율주행 이어서 진행."
3. 새 Claude 세션이 두 문서 + `workflows/agents/*.md` 읽고 컨텍스트 복원
4. **AUTONOMOUS-PLAN.md** 의 사전 결정·페인 분배·brief 프로토콜·핸드오프 절차 그대로 따름. 사용자 결정 요청 없음 (Hard stop 발생 시 제외).
5. **다음 진입점**: 5단계 (Autonomous mode 진행 상태 섹션 확인 — 중도 재개라면 거기서 재개).
6. **페인 모델**: pane 0/1 = sonnet (~200K), pane 2 = opus (1M). sonnet 페인은 단계마다 fresh-session 가정 + brief 자급자족 (AUTONOMOUS-PLAN 내 sonnet-aware 운영 규칙 참고).

---

## 프로젝트 목표

shinpr/claude-code-workflows + altmemy/claude-spring-boot 를 참고해 **개인용 Claude Code 마켓플레이스 플러그인** 을 만든다. 핵심:
- **회사처럼 굴러가는 7명 페르소나** (Technoking 팀장 + 6명 전문가)
- **tmux 페인 병렬 워커** — 각 워커가 헤드리스 `claude` 인스턴스로 독립 작업
- **스택 무관 코어** + 갈아끼울 수 있는 **stack-* 플러그인**
- **/codex:rescue 자동 위임** — 같은 에러 2회 반복 시 codex 백그라운드 위임

---

## 진행 체크리스트

### 1단계: 디렉터리·페르소나 (완료)
- [x] 1-1 ~ 1-6: 디렉터리 구조·플러그인 분할·커맨드 라인업·라이프사이클·Stop 정책·인자 형식
- [x] 페르소나 7명 작성 (`workflows/agents/*.md`)
- [x] codex-rescue 정책 적용 (페르소나 인라인)
- [x] 페르소나 범용화 (스택 종속 제거)
- [x] P0~P2 9개 디테일 보강
- [x] 압축 (-15%)
- [x] KST + 한국어 본문 정책 적용
- [x] 페인 명명 + 레이아웃 (worker-be/fe/qa/review)

### 2단계: 컨벤션 (C 단계 완료)
- [x] C-1: `.claude-team/` 디렉터리 트리·명명 규약·파일 분류·archive 정책
- [x] C-2: ticket 7종 schema (Work `T-NNNN` / Review `RV-NNNN` (rescue validation) / Review report `RR-T-NNNN-N` / Rescue `RESCUE-<ts>` / Inbox `INBOX-<ts>-<pane>` / Backlog `BL-NNNN` / Handoff `HANDOFF-<ts>`)
- [x] C-3: `workers/registry.json` + 카운터 정책 (4자리 zero-pad)
- [x] C-4: tmux 페인 명명 + dispatch 규약 + 헤드리스 호출

### 3단계: 매니페스트 (B 단계 완료)
- [x] B-1: `.claude-plugin/marketplace.json`
- [x] B-2: `workflows/.claude-plugin/plugin.json`
- [x] B-3: `stack-kotlin-spring/.claude-plugin/plugin.json`
- [x] B-4: `stack-nextjs/.claude-plugin/plugin.json`

**B 단계 메모**: agents/skills/commands 는 plugin.json 본문에 적지 않음 — Claude Code 가 디렉터리 컨벤션(`agents/`, `skills/`, `commands/`)으로 자동 검출. A·5단계에서 파일만 추가하면 plugin.json 재수정 불필요. shinpr 의 `dev-workflows/.claude-plugin/plugin.json` 도 동일 패턴.

### 4단계: 스킬 본문 (A 단계 완료)
- [x] workflows 코어 스킬 8개: `coding-principles`, `documentation-criteria`, `testing-principles`, `git-flow`, `ticket-protocol`, `tmux-worker-protocol`, `adversarial-review-bridge`, `orchestration-guide`
- [x] stack-kotlin-spring 스킬 3개: `kotlin-spring-boot-core`, `data-access`, `testing-kotlin`
- [x] stack-nextjs 스킬 3개: `nextjs-core`, `frontend-data`, `testing-nextjs`

**A 단계 메모**: 모든 스킬 본문 영어 (frontmatter + body). 사용자 산출물 본문(PRD/Design/ADR/Diagnose body)은 한국어 정책. `When this skill conflicts with the AC` 종결 섹션을 모든 스킬에 일관 적용 → AC 와 충돌 시 결정 트리 명시. 코어 8개는 codex hard-dep 정책(complexity 무관 review/rescue 강제) 반영. 다음 진입점: 5단계 슬래시 커맨드 12개.

**A 단계 review/fix (2026-05-11)**: 14개 SKILL 검토 후 P0 7건 + P1 25건 + cross-cutting 3건 (P1-X1 종결 섹션 one-liner OK 정책, P1-X2 canonical 빌드/테스트 명령 4파일 추가, P1-X3 layering 우선순위 5스택파일 추가) 일괄 적용. pane 0/1/2 셋이 분담 — race-free (1파일 1pane). 핵심 변경: review report 접두사 `RV-T-NNNN-N` → **`RR-T-NNNN-N`** (5파일 일괄), `kind: directive` enum 추가 (mid-ticket pivot 채널), `Investigator` → `Galaxy Brain` (페르소나 슬러그 정합), 백엔드 핀 4개 (JDK 24 / Kotlin 2.2.21 / Spring Boot 4.0.6 / Gradle Kotlin DSL — `kotlin-spring-boot-core` 만, 의존성 좌표 본문 박지 않음), 프론트 핀 (Next.js 15 / React 19 / Node ≥20.11 / TS 5 / pnpm 9 / TanStack Query v5+ / MSW v2+ — 4파일), Clean Architecture (단순) 명시 + DIP repository 인터페이스 application 레이어 위치, JPA entity 룰 (`data class` 금지·수동 `open`/`no-arg` 금지·`allOpen` 자동 처리), Coroutine `@Transactional` 컨텍스트 누수 footgun, Flyway `outOfOrder=false` BLOCKING, JdbcClient over JdbcTemplate, Server Action authN ≠ authZ + useTransition, SSR HydrationBoundary 패턴 추가. 14파일 합계 2,384줄 → 2,505줄 (+121, 필수 컨텐츠 추가 후 압축 net으로 흡수).

### 5단계: 슬래시 커맨드 본문 12개 (완료)
- [x] `/feat`, `/design`, `/task`, `/review`, `/diagnose`, `/setup-team`, `/status`, `/abort`, `/handoff`, `/hire`, `/show-team`, `/cleanup`

**5단계 메모 (2026-05-11)**: 12 파일 합 898줄 (50–100줄 범위 모두 준수). 페인 분배 race-free 4-4-4 (pane 0 셋업·관리: setup-team 82L / show-team 56L / status 78L / cleanup 80L · pane 1 단일책임: task 75L / diagnose 82L / abort 98L / handoff 99L · pane 2 라이프사이클: feat 70L / design 53L / review 53L / hire 72L). 모든 커맨드가 12/12 비율로 codex:status pre-flight + 표준 3-section 구조 (pre-flight → SKILL 위임 → expected output) 준수. 위임 SKILL 참조 8개 모두 실재 (adversarial-review-bridge / coding-principles / documentation-criteria / git-flow / orchestration-guide / testing-principles / ticket-protocol / tmux-worker-protocol). 새 추상화 0건 — 기존 SKILL 명만 참조. 본문 영어 일관, frontmatter `description` 한 줄 자연언어 트리거. setup-team 만 pre-flight 1·3 자기제외 (자기가 만드는 것). 다음 진입점: 6단계 스크립트·훅 7개.

### Autonomous mode 진행 상태 (자율 모드 매 단계 후 갱신)

```
5단계: ✓ (12 파일, 898줄)
6단계: ✓ (7 파일, 721줄)
7단계: ✓ (1 파일, 92줄)
8단계: ✓ (6 파일, 653줄)
[5-8단계 자율 모드 종료]

REVIEW round (codex-only review 정책 정합 + 모호함 보강 + 압축) ✓
  pane 0 (3 파일): technoking.md +2L ✓ / ticket-protocol/SKILL.md +32L ✓ / commands/review.md -1L ✓
  pane 1 (3 파일): the-roastmaster.md +8L ✓ / orchestration-guide/SKILL.md +9L ✓ / tmux-worker-protocol/SKILL.md +6L ✓
  pane 2 (3 작업): AUTONOMOUS-PLAN 재작성 ✓ / docs/ticket-protocol.md ✓ (137→172L) / 최종 cross-cutting 검증 ✓
  pane 2 추가 sweep (5건): 4 워커 페르소나의 `RV-T-{NNN}-{slug}` → `RV-NNNN-<slug> (type:review § 4b)` + orchestration-guide L79 "full diff walk" → codex-only 표현 + adversarial-review-bridge L40 `kind: codex_result` → 직접 폴링 표현 ✓
[REVIEW round 자율 모드 종료 — AUTONOMOUS-PLAN.md 삭제 가능]

9단계: 진행 중 (Step 0-2 ✓ 환경 사전조건 통과 / Step 3 ◻ codex-plugin-cc install 부터 재개 — 세션 재시작 필요)
```

페인 0/1/2 분배·brief 프로토콜·컨텍스트-부족 핸드오프는 `AUTONOMOUS-PLAN.md` 참고.

### 6단계: 셋업 스크립트 + 훅 (완료)
- [x] `workflows/scripts/tmux-setup.sh` (118L)
- [x] `workflows/scripts/worker-launch.sh` (128L, VERIFY 마커 1개)
- [x] `workflows/scripts/ticket-publish.sh` (108L)
- [x] `workflows/scripts/ticket-poll.sh` (115L)
- [x] `workflows/hooks/block-dangerous.sh` (92L)
- [x] `stack-kotlin-spring/hooks/stop-verification.sh` (76L)
- [x] `stack-nextjs/hooks/stop-verification.sh` (84L)

**6단계 메모 (2026-05-11)**: 7 파일 합 721줄. 페인 분배 race-free 3-2-2 (pane 0 워크플로 코어 3 = worker-launch + ticket-publish + ticket-poll 351줄 · pane 1 셋업+훅 2 = tmux-setup + block-dangerous 210줄 · pane 2 스택 훅 페어 2 = kotlin/nextjs stop-verification 160줄). 모든 sh 파일이 `#!/usr/bin/env bash` + `set -euo pipefail` + `IFS=$'\n\t'` + exec bit 일관 (7/7 통과). Exit code 표준 (0/1/2/3/4) — 0=ok, 1=generic, 2=preflight/blocked, 3=lock contention, 4=bad args. counter 락 패턴 (`mkdir .claude-team/.counter.lock`, 30 retry) 일관. `worker-launch.sh` 의 `claude` CLI flag 가정 (`--print --append-system-prompt`) 은 VERIFY 마커로 9단계 위임 (의도된 미검증). jq/python3 이중 fallback 정책 (없으면 sed) — 외부 의존성 graceful degradation. 스택 훅: kotlin = `./gradlew test`, nextjs = `pnpm test` (canonical commands 인용). non-stack 환경 silent skip (exit 0), tooling 누락 = block (exit 2). `CLAUDE_TEAM_SKIP_VERIFY=1` 명시 override 채널. `block-dangerous.sh` self-test 통과 (rm -rf 차단 ✓, ls 통과 ✓, non-Bash 통과 ✓). 다음 진입점: 7단계 CLAUDE.md.

### 7단계: 글로벌 가이드 (완료)
- [x] `CLAUDE.md` (프로젝트 루트, 글로벌 컨벤션 요약, 92줄)

**7단계 메모 (2026-05-11)**: 한국어 본문 92줄 (가이드 80-120 안). 5개 섹션 — 한 단락 소개 + 7 페르소나 표 + 핵심 컨벤션 11개 표 + 디렉터리 트리 + 스킬 구성 맵 + 12 커맨드 카테고리 + Claude 가 잊지 말 것 10개. BUILD-PROGRESS 의 "합의된 디자인 결정" 섹션 압축본 + globally pinned 정책. 페르소나·스킬·커맨드 충돌 시 이 파일 우선. 다음 진입점: 8단계 사용자 문서 6개.

### 8단계: 사용자 문서 (완료)
- [x] `README.md` (69L) — 마켓플레이스 설치·첫 실행 entry-point
- [x] `docs/installation.md` (166L) — 사전조건 + /codex:setup + 마켓 추가 + /setup-team + 트러블슈팅 + sample settings.local.json
- [x] `docs/personas.md` (89L) — 7명 카드, /show-team 출력과 정합
- [x] `docs/ticket-protocol.md` (137L) — 사용자 관점 .claude-team/ 구조 + 수동 개입
- [x] `docs/tmux-layout.md` (92L) — 페인 그림 + tmux 단축키 + 워커 모니터링
- [x] `docs/git-flow.md` (100L) — 브랜치 명명 + PR 템플릿 + hotfix 흐름

**8단계 메모 (2026-05-11)**: 6 파일 합 653줄 (가이드 ~630, ±20% 안). 페인 분배 race-free 2-2-2 (pane 0 entry-point: README + installation 235L · pane 1 operational: ticket-protocol + tmux-layout 229L · pane 2 라이프사이클·git: personas + git-flow 189L). 본문 한국어 일관, 코드/커맨드 예시 영어 그대로. 페르소나 슬러그 정합 (CLAUDE.md == docs/personas.md, 7명 동일). RR-T-NNNN-N (review report) vs RV-NNNN (rescue validation) 구분 명시. settings.local.json 샘플 docs/installation.md 에 첨부. 다음 단계: 9단계 (사용자 환경 스모크 테스트).

### REVIEW round (2026-05-11) — codex-only review 정합 + 모호함 보강 + 압축

**배경**: 사용자 정책 변경 (Roastmaster 자체 리뷰 폐기, codex `--background` 비차단 dispatch 강제) 후 1차 8 파일 갱신. 그 후 cross-cutting 점검에서 추가 모호함·잔재 10건 발굴 — 본 라운드는 그것의 일괄 정합·압축 패스.

**발굴된 10건 patch**:
1. technoking persona — 옛 명명 잔재 4건 (`PR-{n}-rev{k}` / `RV-{NNN}-PR{n}` / `T-{NNN}.json` / `RV-{NNN}.json`) → `RR-T-NNNN-N` / `RV-NNNN` / `INBOX-<ts>-<pane>` 표준.
2-4. the-roastmaster persona — `-rev{k}` suffix → `{round}` (3건: alg path / report header / Reporting Format) + 옛 verdict `REQUEST_CHANGES`/`ESCALATE` → `APPROVE | COMMENT | BLOCKING`.
5. ticket-protocol § 5 inbox `kind` enum +5: `review_request | review_complete | pattern_stuck | fix_pushed | needs_reblock` + `reason` 에 `codex_review_timeout` 추가.
6. ticket-protocol § 4 `type: review` 의 두 sub-case 정의 (4a 일반 PR review / 4b rescue validation) — 같은 `RV-NNNN` 카운터 공유, schema 필드로 구분.
7. orchestration-guide step 9 보강 #1: BLOCKING 후 round+1 review ticket 발행 주체 = Technoking (워커 `kind: fix_pushed` 수신 후 발행) 명시.
8. orchestration-guide step 9 보강 #2: COMMENT 후 워커 inline push 는 새 round 트리거 X (격상 필요 시 `kind: needs_reblock`) 명시.
9. commands/review.md — 비공식 `role: review_only` 제거, `type: review` (§ 4a) 로 흡수.
10. tmux-worker-protocol inbox kind enum — ticket-protocol § 5 와 동기화 (+5 kind 추가).

**페인 분배 (file-disjoint 3-3-3)**:
- pane 0 (sonnet, 워크플로 stateful): technoking.md / ticket-protocol/SKILL.md / commands/review.md
- pane 1 (sonnet, 라이프사이클·페르소나): the-roastmaster.md / orchestration-guide/SKILL.md / tmux-worker-protocol/SKILL.md
- pane 2 (opus, cross-cutting): AUTONOMOUS-PLAN 재작성 ✓ / docs/ticket-protocol.md inbox 표 + 리뷰 라운드 흐름 추가 ✓ (137→172L) / 최종 grep 검증 ◻

**완료 조건 (cross-cutting grep)**:
- 옛 review report path 잔재 (`PR-{n}-rev{k}` / `RV-{NNN}-PR` / `RR-T-{NNN}-rev`) = 0
- 옛 verdict 잔재 (`REQUEST_CHANGES`) = 0
- inbox kind 정의·사용 정합 — ticket-protocol enum 이 사용처 9 kind 모두 포함
- 정상 (APPROVE/COMMENT) + 예외 (BLOCKING/pattern_stuck/codex_review_timeout/rescue_failed/3-round) 흐름 모두 한 번 읽기로 완결

새 추상화 0건 — 기존 enum 확장만. 새 카운터·디렉터리·파일 추가 X. 압축: net 변화 측정 후 흡수 가능한 영역 압축. 다음 진입점: cross-cutting 검증 후 AUTONOMOUS-PLAN.md 삭제.

### 9단계: 검증 (진행 중)

**진행 상태 (2026-05-11)**:
- [x] **Step 0**: `claude --help` flag 검증 — `--print` ✓ + `--append-system-prompt <prompt>` ✓ 존재 확인. **worker-launch.sh L107 VERIFY 마커 가정 정확 — 수정 불필요**. 보너스: `--plugin-dir <path>` flag 발견 (마켓 publish 없이도 로컬 plugin 직접 로드 가능).
- [x] **Step 1**: tmux 3.6a ✓ (요구 ≥ 3.2 통과).
- [x] **Step 2**: codex CLI 설치 — `brew install codex` 로 `codex-cli 0.130.0` at `/opt/homebrew/bin/codex`. `codex login status` = "Logged in using ChatGPT" (인증 완료).
- [ ] **Step 3 (다음 진입점, 세션 재시작 후)**: codex-plugin-cc Claude Code plugin install. 현 세션에서 `/codex:status` = "Unknown command" 응답 — plugin 미설치 확인. **세션 재시작 후 아래 명령 순서로 진행**:
  ```
  /plugin marketplace add openai/codex-plugin-cc
  /plugin install codex-plugin-cc
  /codex:status                  # "ready" 떠야 다음 진행
  ```
- [ ] **Step 4**: 우리 마켓 install.
  ```
  /plugin marketplace add /Users/jeondoh/develop/workspace/personal-claude
  /plugin install workflows@personal-claude-code
  # 옵션: stack-kotlin-spring / stack-nextjs
  ```
- [ ] **Step 5**: `/setup-team` 첫 실행. tmux 새 세션 (`claude-team`) + 4 워커 페인 + `.claude-team/` 디렉터리 생성. 여기서 worker-launch.sh 첫 실 발화 (이미 flag 검증됐으니 통과 예상).
- [ ] **Step 6**: `/show-team` — 7 페르소나 + 4 페인 PID alive 확인.
- [ ] **Step 7**: `/feat "hello world endpoint"` 같은 trivial small 요청 — small 자동 라우팅으로 `/task` 진입 예상. lifecycle 1회전 (구현 → codex 비차단 dispatch → verdict → 머지) 관찰.
- [ ] **Step 8**: 통과 시 `git push` + 마켓 publish (`/plugin marketplace add sideholic/personal-claude-code` 정식 경로 검증).

**환경 사전조건 정리 (확인 완료)**:
- brew 5.1.10 ✓ · node 25.9.0 ✓ · npm 11.12.1 ✓
- tmux 3.6a ✓ · codex 0.130.0 ✓ (ChatGPT 인증)
- claude CLI flag (`--print` / `--append-system-prompt`) ✓
- repo cwd `/Users/jeondoh/develop/workspace/personal-claude` 에서 진행 (페인 0/1/2 모두 이 cwd)

**세션 재시작 후 시작 메시지 (사용자가 입력)**:
> "BUILD-PROGRESS.md 의 9단계 진행 상태 읽고 Step 3 부터 이어서 진행."

자동 ⏵ 이어서: codex-plugin-cc install 명령 안내 → `/codex:status` 결과 → 다음 step.

---

## 합의된 디자인 결정 (요약)

### 페르소나 7명

| # | 이름 | 직책 | 모델 | 페인 |
|---|---|---|---|---|
| 1 | **Technoking** | Tech Lead | sonnet | `main` |
| 2 | **Spec Shaman** | Product Owner | sonnet | subagent (no pane) |
| 3 | **Galaxy Brain** | System Architect | **opus** | subagent (no pane) |
| 4 | **Persistence Paladin** | Backend (DB·security 흡수) | sonnet | `worker-be` |
| 5 | **Pixel Wizard** | Frontend (디자인·a11y 흡수) | sonnet | `worker-fe` |
| 6 | **What-If Witch** | QA | sonnet | `worker-qa` |
| 7 | **The Roastmaster** | Code Reviewer | **opus** | `worker-review` |

### 페인 레이아웃

```
┌──────────────┬──────────────┐
│              │ worker-fe    │
│ main         ├──────────────┤
│ (Technoking) │ worker-be    │
│              ├──────────────┤
├──────────────┤ worker-qa    │
│ worker-      │              │
│ review       │              │
└──────────────┴──────────────┘
```
- 좌측 (50%): `main` 위 / `worker-review` 아래
- 우측 (50%): `worker-fe` 상 / `worker-be` 중 / `worker-qa` 하

### 슬래시 커맨드 12개

| # | 커맨드 | description (영어) |
|---|---|---|
| 1 | `/feat` | Start full feature lifecycle (PRD → design → implement → review → merge) |
| 2 | `/design` | Generate PRD and design docs only, no implementation |
| 3 | `/task` | Run a small single-purpose task or bug fix |
| 4 | `/review` | Trigger Roastmaster review on an existing PR (codex adversarial-review) |
| 5 | `/diagnose` | Investigate a bug, trace failure path, propose fixes |
| 6 | `/setup-team` | Bootstrap .claude-team and launch tmux worker panes |
| 7 | `/status` | Show worker panes, ticket queue, and progress board |
| 8 | `/abort` | Safely cancel in-progress tickets and clean up worktrees |
| 9 | `/handoff` | Serialize current context into a handoff ticket for next session |
| 10 | `/hire` | Hire a new team member with a custom persona and role |
| 11 | `/show-team` | Display team roster with personas, roles, and pane assignments |
| 12 | `/cleanup` | Archive stale tickets/rescues/reviews; free disk space |

### 11단계 `/feat` 라이프사이클

1. 접수·복잡도 판정 (Technoking) — small/medium/large
2. PRD 작성 (Spec Shaman)
3. PRD 승인 [Stop] (large 만)
4. 설계·ADR + 인터페이스 (Galaxy Brain)
5. 설계+인터페이스 승인 [Stop] (medium=PRD+설계 통합 / large=설계 단독)
6. 작업 분해·티켓 발행 (Technoking) — large 시 batch approval [Stop]
7. 인수 테스트 선행 (What-If Witch, fail 상태 커밋)
8. 구현 (Paladin · Wizard 병렬)
9. PR 생성·리뷰 루프 (Technoking → Roastmaster, 최대 3회)
10. 통합·E2E 검증 (What-If Witch, 최대 2회)
11. 머지·보고 (Technoking)

**Stop 정책 (B 패턴, shinpr-style)**:
- small: 0 / medium: 1 (5단계 batch) / large: 3 (3,5,6단계)
- 머지 직전 stop 없음 (batch approval 후 자율 실행)
- 자동 escalation: requirements change / architectural change / untestable AC / worker escalation_needed

**품질 게이트 (complexity 무관, 항상 강제)**:
- 9단계 PR 리뷰 루프 (Technoking → Roastmaster, 최대 3회) — small `/task` 포함 전체 적용
- Roastmaster 는 매 PR 마다 `/codex:adversarial-review` 호출
- 같은 에러 2회 / `pattern_stuck` 트리거 시 자동 rescue
- 즉, 1단계 small 라우팅 (`/task`) 도 페르소나 일부만 사용할 뿐 리뷰·rescue 게이트는 동일

### 복잡도 판정

| 등급 | 룰 |
|---|---|
| small | 1–2 파일, 단일 영역, DB/API/auth/deps 변경 없음 → `/task` 라우팅 |
| medium | 3–5 파일, 작은 DB or 신규 API 1–2개, 기존 도메인 |
| large | 6+ 파일, 양 영역, 큰 DB OR 신규 도메인 OR 외부 통합 |

**즉시 large 트리거**: auth/permission 변경 / DB 스키마 마이그레이션 / 신규 도메인 / 외부 결제·법규.

### codex 통합 정책

**의존성 등급**: **HARD**. codex CLI + 인증 + `codex-plugin-cc` 가 모두 갖춰지지 않으면 어떤 ticket 도 진행 불가. soft/degraded 모드 없음.

**적용 범위**: complexity (small/medium/large) **무관 전체**. complexity 는 계획·문서·승인 부담만 결정하고, **품질 게이트(Roastmaster 리뷰 + `/codex:adversarial-review` + 자동 rescue) 는 모든 ticket 에 동일하게 강제**.

**초기화**: `/setup-team` 첫 단계에서 `/codex:status` 검증. fail 시 즉시 halt + "/codex:setup 실행 후 재시도" 안내. codex 인증·CLI 설치는 codex-plugin-cc 의 `/codex:setup` 에 위임 (우리가 재구현 X).

**Auto-rescue triggers** (Technoking 자동 발동, 사용자 승인 없음):
- 워커 빌드/테스트 같은 실패 2회 (`error_signature` 매칭)
- Roastmaster `pattern_stuck: true` (같은 BLOCKING 2회 연속)

**제외**: requirements change / architectural redesign / untestable AC → 표준 escalation.

**절차**: `/codex:rescue --background` (signature 는 prompt body 에 임베드, flag 가정 X) → Technoking 비차단 (다른 ticket 진행) → patch 도착 시 `rescue/T-NNNN` 브랜치 (codex 가 다른 이름으로 push 하면 Technoking 이 rename) → 새 validation ticket `RV-NNNN-<slug>.md` (큐 최우선) → 원작자 검증 → Roastmaster 가 `RR-T-NNNN-<round>.md` 재리뷰 → 머지.

**rescue 검증도 fail 하면**: `escalation_needed` (auto-rescue 재시도 X, 사용자 호출).

`error_signature` 계산: SHA-1 prefix(8) of `<error_class>:<file>:<line>`.

### 핵심 컨벤션

| 항목 | 규칙 |
|---|---|
| **Ticket ID** | 4-digit zero-pad: `T-0001`, `RV-0042`, `BL-0007`. 9999 초과 시 5자리 자동 확장 |
| **Timestamps** | KST (UTC+9), ISO 8601 with `+09:00` offset (예: `2026-05-10T14:30:00+09:00`). Date-only: `YYYY-MM-DD` |
| **본문 언어 — 사용자 산출물** | 한국어 (PRD body, Design Doc body, ADR body, Diagnose body, Handoff body, Review report body) |
| **본문 언어 — 그 외** | 영어 (페르소나 본문, 스킬, 워커 ticket, inbox JSON, 코드, frontmatter) |
| **Frontmatter (YAML)** | 영어 keys/enums (프로그램틱 파싱) |
| **Counter 관리** | `workers/registry.json` 의 `counters: { T, RV, BL }` 만. RESCUE/HANDOFF 는 timestamp 기반 |

### 디렉터리 구조 (`.claude-team/`)

```
.claude-team/
├── tickets/queue/        ← Technoking 발행
├── tickets/in-progress/  ← 워커 작업 중
├── tickets/done/         ← 완료 (auto-archive 30d)
├── tickets/cancelled/    ← 취소 (auto-archive 7d)
├── reviews/              ← Roastmaster 보고서 (archive 30d after merge)
├── inbox/                ← 워커→Technoking 알림 (transient, 처리 후 삭제)
├── rescues/              ← Technoking rescue 추적 (auto-archive 30d)
├── backlog/              ← OUT-OF-SCOPE (BL-NNNN-*.md)
├── handoff/              ← /handoff 직렬화 (archive on resume)
├── archive/{YYYY-MM}/    ← /cleanup 또는 자동 트리거로 이동
└── workers/registry.json ← pane↔persona↔PID + counters
```

### git 추적 정책

- **추적**: `docs/*` (PRD/Design/ADR/Diagnose)
- **gitignore**: `.claude-team/`, `.worktrees/`

---

## 작성된 파일 (현재, 51개 산출물)

```
personal-claude-code/
├── .claude-plugin/marketplace.json                       ✓ B-1
├── workflows/
│   ├── .claude-plugin/plugin.json                        ✓ B-2
│   ├── agents/                                           ✓ 1단계 (7개)
│   │   ├── technoking.md
│   │   ├── spec-shaman.md
│   │   ├── galaxy-brain.md
│   │   ├── persistence-paladin.md
│   │   ├── pixel-wizard.md
│   │   ├── what-if-witch.md
│   │   └── the-roastmaster.md
│   ├── commands/                                         ✓ 5단계 (12개)
│   │   ├── feat.md, design.md, task.md, review.md
│   │   ├── diagnose.md, setup-team.md, status.md, abort.md
│   │   └── handoff.md, hire.md, show-team.md, cleanup.md
│   ├── scripts/                                          ✓ 6단계 (4개)
│   │   ├── tmux-setup.sh, worker-launch.sh
│   │   └── ticket-publish.sh, ticket-poll.sh
│   ├── hooks/                                            ✓ 6단계 (1개)
│   │   └── block-dangerous.sh
│   └── skills/                                           ✓ A 단계 코어 (8개)
│       ├── coding-principles/SKILL.md
│       ├── documentation-criteria/SKILL.md
│       ├── testing-principles/SKILL.md
│       ├── git-flow/SKILL.md
│       ├── ticket-protocol/SKILL.md
│       ├── tmux-worker-protocol/SKILL.md
│       ├── adversarial-review-bridge/SKILL.md
│       └── orchestration-guide/SKILL.md
├── stack-kotlin-spring/
│   ├── .claude-plugin/plugin.json                        ✓ B-3
│   ├── hooks/                                            ✓ 6단계 (1개)
│   │   └── stop-verification.sh
│   └── skills/                                           ✓ A 단계 스택 (3개)
│       ├── kotlin-spring-boot-core/SKILL.md
│       ├── data-access/SKILL.md
│       └── testing-kotlin/SKILL.md
├── stack-nextjs/
│   ├── .claude-plugin/plugin.json                        ✓ B-4
│   ├── hooks/                                            ✓ 6단계 (1개)
│   │   └── stop-verification.sh
│   └── skills/                                           ✓ A 단계 스택 (3개)
│       ├── nextjs-core/SKILL.md
│       ├── frontend-data/SKILL.md
│       └── testing-nextjs/SKILL.md
├── CLAUDE.md                                             ✓ 7단계
├── README.md                                             ✓ 8단계
├── docs/                                                 ✓ 8단계 (5개)
│   ├── installation.md, personas.md
│   ├── ticket-protocol.md, tmux-layout.md
│   └── git-flow.md
└── BUILD-PROGRESS.md
```

총 14 SKILLs (코어 8 + 백엔드 3 + 프론트 3) · 7 페르소나 · 12 커맨드 · 7 스크립트·훅 · 1 글로벌 가이드 · 1 README + 5 docs · 4 매니페스트.

### 설치 명령 (현 시점 동작 확인 가능)
```
/plugin marketplace add sideholic/personal-claude-code
/plugin install workflows@personal-claude-code
/plugin install stack-kotlin-spring@personal-claude-code   # 옵션 (백엔드)
/plugin install stack-nextjs@personal-claude-code           # 옵션 (프론트)
```
> 5단계(슬래시 커맨드) · 6단계(스크립트·훅) 미완. 페르소나·스킬은 로드되지만 사용자가 호출할 슬래시 커맨드는 아직 비어있음.

---

## 다음 단계 상세 (5단계 — 슬래시 커맨드 12개)

### 5단계: 슬래시 커맨드 본문 작성

**작성 위치** (Claude Code 컨벤션):
```
workflows/commands/<command>.md           # 코어 커맨드
stack-kotlin-spring/commands/<...>.md     # (스택 종속이 필요한 경우만)
stack-nextjs/commands/<...>.md
```

각 파일: frontmatter (`description`) + 본문 = "이 명령이 들어오면 너는 이렇게 해라" 트리거 프롬프트.

**작성 순서 권장** (의존성 낮은 → 높은 순):
1. `/setup-team` — `/codex:status` 게이트 + tmux 페인 셋업 + `.claude-team/config.yml` 작성. 다른 모든 커맨드의 사전 조건.
2. `/show-team` — `registry.json` 읽어서 페르소나·페인 매핑 표시 (가벼움).
3. `/status` — 페인 PID + ticket 큐 + 진행 보드.
4. `/task` — small 라우팅. 단일 워커 + 리뷰 + rescue (quality gate 동일).
5. `/feat` — 11단계 라이프사이클 마스터. `orchestration-guide` 스킬 위임.
6. `/design` — `/feat` 의 step 2-5 까지만 (PRD + Design 작성, 구현 X).
7. `/diagnose` — Galaxy Brain (또는 Technoking direct) 호출. `documentation-criteria` Diagnose 섹션.
8. `/review` — 기존 PR 에 Roastmaster + `/codex:adversarial-review` 강제 호출.
9. `/abort` — 진행 ticket 안전 취소 + worktree 정리.
10. `/handoff` — 현재 컨텍스트 직렬화. `.claude-team/handoff/HANDOFF-<ts>.md`.
11. `/hire` — 신규 페르소나 추가 (custom 역할). `workflows/agents/<slug>.md` 생성.
12. `/cleanup` — done 30d / cancelled 7d archive + orphan worktree 제거.

**본문 언어**: 영어 (커맨드 = "그 외" 카테고리). 압축 우선.

**핵심 정책 (모든 커맨드 적용)**:
- Pre-flight: `/setup-team`·`/codex:status` 둘 다 실패 시 즉시 halt.
- 커맨드 본문은 직접 로직 박지 말고 해당 스킬에 위임 (`see orchestration-guide`, `see ticket-protocol`).
- 종결 섹션 형식 통일은 강제 X (one-liner OK 정책 — A 단계 P1-X1 결정).

---

## 사용자 작업 스타일 메모 (다음 세션 Claude 가 알아야)

- **한 번에 한 가지 결정** 만 묻기. 여러 결정 동시 묶지 말 것.
- **"이번에 정하는 것"** 박스로 명시 강조.
- **추천안 + 근거** 항상 제시.
- 사용자가 변경 지시하면 짧게 적용 + 다음 단계 안내.
- **압축 우선**: 페르소나/스킬 본문은 핵심만. 부가 설명·중복 표현 제거.
- **사용자 산출물 한국어, 그 외 영어** 일관 유지.

---

## 참고 레퍼런스

- shinpr/claude-code-workflows — 11단계 라이프사이클·shinpr-style batch approval [Stop] 정책의 영감
- altmemy/claude-code-templates/claude-spring-boot — 역할별 페르소나·hooks 패턴 영감
- openai/codex-plugin-cc — `/codex:adversarial-review`, `/codex:rescue` 활용

---

**다음 세션 시작 시 첫 메시지 예시 (자율주행)**:
> "BUILD-PROGRESS.md 와 AUTONOMOUS-PLAN.md 읽고 자율주행 시작. 5단계부터."

중도 재개 시:
> "BUILD-PROGRESS.md 와 AUTONOMOUS-PLAN.md 읽고 자율주행 이어서 진행."
