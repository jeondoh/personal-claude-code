# personal-claude-code

> Claude Code 를 **회사처럼 굴러가는 7인 페르소나 팀** 으로 운영하는 마켓플레이스 플러그인.

Technoking 이 사용자 요청을 받아 복잡도(small/medium/large)를 판정하고, tmux 페인에서 병렬로 도는 헤드리스 `claude` 워커들에게 ticket 을 분배한다. 모든 PR 은 codex 어드버서리얼 리뷰를 통과해야 머지된다. small 도 예외 없음.

```
┌────────────────────┬────────────────────┐
│                    │ worker-fe          │  Pixel Wizard
│   main             ├────────────────────┤
│  (Technoking)      │ worker-be          │  Persistence Paladin
│                    ├────────────────────┤
├────────────────────┤ worker-qa          │  What-If Witch
│ worker-review      │                    │
│  (Roastmaster)     │                    │
└────────────────────┴────────────────────┘
```

## 어떻게 작동하나

```
사용자 요청
    ↓
Technoking (main 페인)
    ├─ 복잡도 판정 (small / medium / large)
    ├─ Spec Shaman → PRD (medium·large)
    ├─ Galaxy Brain → Design Doc + ADR (medium·large)
    ├─ ticket 분배 → tickets/queue/
    │
    ▼ 워커 페인들이 폴링으로 ticket 픽업
Paladin (worker-be) · Wizard (worker-fe) · Witch (worker-qa)
    ├─ 각자 .worktrees/T-NNNN/ 에서 병렬 작업
    └─ PR push → inbox/ 에 completion 알림
        ↓
Roastmaster (worker-review)
    ├─ /codex:adversarial-review --background (비차단 dispatch)
    └─ verdict 판정: APPROVE / COMMENT / BLOCKING
        ↓ (BLOCKING 2회 = pattern_stuck → 자동 rescue)
        ↓ (워커 에러 2회 = error_2x → 자동 rescue)
Technoking → 머지 → 보고
```

워커 간 직접 통신 없음. **모든 조율은 `.claude-team/` 디렉터리의 파일** (ticket / inbox / review report) 로만 이뤄진다. 자세한 데이터 모델은 [`workflows/skills/ticket-protocol/SKILL.md`](workflows/skills/ticket-protocol/SKILL.md).

## 들어있는 것

이 마켓플레이스는 **3 개 플러그인** 으로 나뉜다. `workflows` 는 필수, 나머지는 프로젝트 스택에 맞춰 골라 깐다.

| 플러그인 | 종류 | 역할 |
|---|---|---|
| `workflows` | 코어 (필수) | 7 페르소나, 8 스킬, 12 슬래시 커맨드, tmux/ticket 스크립트, 안전 훅 |
| `stack-kotlin-spring` | 스택 (옵션) | Kotlin · Spring Boot 코딩·데이터 접근·테스트 규약 |
| `stack-nextjs` | 스택 (옵션) | Next.js · TypeScript 코딩·데이터·테스트 규약 |

### `workflows` — 스택 무관 코어

페르소나·라이프사이클·ticket 프로토콜·codex 게이트가 모두 여기 있다. 어떤 언어/프레임워크 프로젝트든 이 플러그인 하나면 7 인 팀 운영이 가능. 실제 코딩 시 워커들은 `coding-principles` / `testing-principles` 같은 **스택 무관** 원칙을 적용한다.

### `stack-*` — 스택별 스킬 묶음

`stack-*` 플러그인은 **그 스택만의 추가 스킬** 을 얹는 레이어다. 예를 들어 `stack-kotlin-spring` 은 워커에게 다음을 추가로 가르친다:

- `@Transactional` 코루틴 컨텍스트 누수 패턴 회피
- JPA entity 에서 `data class` 금지 (Hibernate 와 충돌)
- Flyway migration 의 `outOfOrder=false` 강제
- `JdbcClient` 우선 (Spring 6+ 이후 `JdbcTemplate` 대체)

이런 스택 고유 함정을 워커가 자동으로 안다는 뜻. `stack-nextjs` 도 Server Components / Server Actions / HydrationBoundary 같은 Next.js 고유 패턴을 동일하게 다룬다.

**버전 핀 없음.** 각 스택 스킬은 학습 데이터 기반의 기본 권장값만 갖고 있고, **실제 적용 시점에 프로젝트의 `build.gradle.kts` / `package.json` 을 워커가 직접 읽는다.** 학습 데이터에 없는 새 버전이라면 공식 문서로 검증 (detect-and-verify 프로토콜).

### 다른 언어로 커스텀 — 직접 만들기

내가 쓰는 스택 (Go·Python·Rust·Swift 등) 에 맞는 `stack-*` 플러그인을 직접 만들 수 있다. 권장 골격:

```
stack-<name>/
├── .claude-plugin/plugin.json        # name, version, description, license
├── skills/
│   ├── <name>-core/SKILL.md          # 언어/프레임워크 컨벤션
│   ├── data-access/SKILL.md          # (백엔드라면) ORM/마이그레이션 규약
│   └── testing-<name>/SKILL.md       # 테스트 프레임워크 규약
└── hooks/
    └── stop-verification.sh          # 워커 turn 끝날 때 빌드/테스트 자동 검증
```

`stack-kotlin-spring/` 또는 `stack-nextjs/` 를 복사해 출발점으로 삼는 게 가장 빠르다. 마켓플레이스의 `marketplace.json` 에 plugin entry 추가 후 `/plugin install` 로 사용.

## 설치

```bash
/plugin marketplace add sideholic/personal-claude-code
/plugin install workflows@personal-claude-code

# 스택 사용 시 골라 설치 (둘 다 깔아도 됨)
/plugin install stack-kotlin-spring@personal-claude-code
/plugin install stack-nextjs@personal-claude-code
```

## 첫 실행

```bash
/codex:setup       # codex CLI 인증 (HARD 의존성, openai/codex-plugin-cc)
/setup-team        # claude-team tmux 세션 + 페인 5개 + .claude-team/ 디렉터리 셋업
/feat <요청>        # 전체 11단계 라이프사이클
# 또는
/task <요청>        # small 작업 (1–2 파일, 단일 영역)
```

`/setup-team` 은 새 tmux 세션 `claude-team` 에 페인을 펴고 각 워커에 헤드리스 `claude` 를 띄운다. 다른 터미널에서 `tmux attach -t claude-team` 으로 진행 상황 확인.

## 7인 팀

| 이름 | 직책 | 모델 | 페인 |
|---|---|---|---|
| **Technoking** | Tech Lead — 라이프사이클·디스패치·머지 게이트 | sonnet | `main` |
| **Spec Shaman** | Product Owner — PRD | sonnet | subagent |
| **Galaxy Brain** | System Architect — Design Doc · ADR | **opus** | subagent |
| **Persistence Paladin** | Backend — DB · 서버 보안 흡수 | sonnet | `worker-be` |
| **Pixel Wizard** | Frontend — UI · a11y · 프론트 보안 흡수 | sonnet | `worker-fe` |
| **What-If Witch** | QA — 인수·통합·E2E | sonnet | `worker-qa` |
| **The Roastmaster** | Code Reviewer — codex 디스패치 + verdict | **opus** | `worker-review` |

자세한 카드: [`docs/personas.md`](docs/personas.md).

## 슬래시 커맨드 12개

### 라이프사이클

| 커맨드 | 용도 | 언제 쓰나 |
|---|---|---|
| `/feat <요청>` | 전체 11 단계 라이프사이클 (PRD → 설계 → 구현 → 리뷰 → 머지) | 신규 기능. medium·large 면 PRD/Design Stop 받음 |
| `/design <요청>` | PRD + Design Doc + ADR 만 생성, 구현은 안 함 | 방향 검증·이해관계자 합의 단계에서 산출물만 필요할 때 |
| `/task <요청>` | small 단발성 변경 (1–2 파일, 단일 영역, DB/auth 없음) | 작은 버그 수정, 한 함수 리팩토링 |
| `/review <PR#>` | 기존 PR 에 Roastmaster 리뷰 재실행 (codex 어드버서리얼) | 수동 수정 후 재리뷰, 외부에서 열린 PR 감사 |

### 진단·운영

| 커맨드 | 용도 | 언제 쓰나 |
|---|---|---|
| `/diagnose <증상>` | 버그 조사·실패 경로 추적·수정 제안 (구현 X) | 원인을 모를 때, 다른 사람이 만든 버그 짚고 갈 때 |
| `/setup-team` | `.claude-team/` 디렉터리 + tmux 페인 + 워커 부팅 | 최초 1회 + 워커가 죽었을 때 재기동 |
| `/status` | 워커 페인 상태, ticket 큐, 진행 중 작업, 최근 완료 보드 | 지금 뭐가 돌고 있는지 한눈에 보고 싶을 때 |
| `/abort <T-NNNN>` | 진행 중 ticket 취소, 워커 정지, 워크트리 정리 | 잘못된 방향으로 가고 있을 때 중단 |

### 직렬화·확장

| 커맨드 | 용도 | 언제 쓰나 |
|---|---|---|
| `/handoff` | 현재 오케스트레이터 컨텍스트를 다음 세션용 ticket 으로 직렬화 | 컨텍스트 차서 새 세션으로 넘어가야 할 때 |
| `/hire <역할>` | 커스텀 페르소나 추가 (예: DevOps Druid, Data Diviner) | 기본 7 인 팀에 프로젝트 특화 역할 필요할 때 |
| `/show-team` | 7 페르소나 + 모델 + 페인 + PID 로스터 출력 | 팀이 다 살아있는지 확인 |
| `/cleanup` | 오래된 ticket/review/rescue 아카이브, 고아 워크트리 제거 | 주기적 청소 (혹은 디스크 정리) |

## 핵심 정책

- **codex 는 HARD 의존성** — `/codex:status` 가 ready 가 아니면 어떤 ticket 도 진행 안 됨. degraded 모드 없음.
- **품질 게이트는 complexity 무관 전체 적용** — `/task` 도 codex 어드버서리얼 리뷰 + 자동 rescue 게이트 동일.
- **자동 rescue** — 같은 에러 2회 (`error_2x`) 또는 Roastmaster `pattern_stuck` 시 사용자 승인 없이 codex 에 위임.
- **Stop 정책 (B 패턴)** — small = 0 / medium = 1 (PRD+Design 통합 Stop) / large = 3 (PRD · Design · batch). 머지 직전 Stop 없음.
- **사용자 산출물은 한국어, 그 외는 영어** — PRD · Design · ADR · commit body · PR body · review report = 한국어. 페르소나·스킬·코드·conventional commit prefix · YAML key = 영어.

자세한 정책: [`CLAUDE.md`](CLAUDE.md) (globally pinned, 충돌 시 최우선).

## 요구사항

| 항목 | 버전·설명 |
|---|---|
| Claude Code | 최신 (CLI / 웹 / VS Code 중 하나) |
| tmux | ≥ 3.2 (pane title 지원) |
| codex CLI | `/codex:setup` 이 설치·인증까지 안내 |
| shell | bash 3.2+ / zsh — macOS 기본 bash 호환 |
| (백엔드 스택만) | JDK + Gradle (버전은 프로젝트 따라감) |
| (프론트 스택만) | Node ≥ 20.11 + pnpm 9+ (`corepack enable pnpm`) |

## 더 알아보기

| 문서 | 내용 |
|---|---|
| [`docs/installation.md`](docs/installation.md) | 사전조건 · 설치 · 첫 ticket · 트러블슈팅 |
| [`docs/personas.md`](docs/personas.md) | 7 페르소나 카드 (역할·도구·말투) |
| [`docs/ticket-protocol.md`](docs/ticket-protocol.md) | `.claude-team/` 구조와 수동 개입 |
| [`docs/tmux-layout.md`](docs/tmux-layout.md) | 페인 레이아웃 · 모니터링 단축키 |
| [`docs/git-flow.md`](docs/git-flow.md) | 브랜치 · 커밋 · PR 컨벤션 |
| [`CLAUDE.md`](CLAUDE.md) | 글로벌 정책 (전 페르소나·스킬·커맨드 적용) |
| [`workflows/skills/orchestration-guide/SKILL.md`](workflows/skills/orchestration-guide/SKILL.md) | 11 단계 라이프사이클 내부 동작 |
| [`workflows/skills/ticket-protocol/SKILL.md`](workflows/skills/ticket-protocol/SKILL.md) | ticket 7 종 schema + 상태 전이 |

## 라이선스

MIT.
