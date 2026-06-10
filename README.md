# personal-claude-code

> Claude Code 를 **회사처럼 굴러가는 7인 페르소나 팀** 으로 운영하는 마켓플레이스 플러그인.

요청을 받으면 Tech Lead 가 복잡도(small/medium/large)를 판정한다. 작업을 잘게 쪼개 tmux 페인의 워커들에게 분배하고, 모든 PR 은 `codex` 어드버서리얼 리뷰를 통과해야 머지된다 — 작은 변경(`small`)도 예외 없음.

```
┌────────────────────┬────────────────────┐
│                    │ worker-fe          │  Pixel Wizard (Frontend)
│   main             ├────────────────────┤
│  (Technoking)      │ worker-be          │  Persistence Paladin (Backend)
│                    ├────────────────────┤
├────────────────────┤ worker-qa          │  What-If Witch (QA)
│ worker-review      │                    │
│  (Roastmaster)     │                    │
└────────────────────┴────────────────────┘
```

## 요구사항

| 항목 | 버전·설명 |
|---|---|
| **Claude Code** | 최신 (CLI / 웹 / VS Code 중 하나) |
| **tmux** | ≥ 3.2 (페인 타이틀 지원) |
| **codex CLI** | 필수 의존성 — `/codex:setup` 이 설치·인증까지 안내 |
| **shell** | bash 3.2+ / zsh — macOS 기본 bash 호환 |
| (백엔드 스택만) | JDK + Gradle (버전은 프로젝트 따라감) |
| (프론트 스택만) | Node ≥ 20.11 + pnpm 9+ (`corepack enable pnpm`) |

## 설치

```bash
/plugin marketplace add sideholic/personal-claude-code
/plugin install workflows@personal-claude-code

# 스택은 프로젝트에 맞춰 골라 깐다 (둘 다 깔아도 됨)
/plugin install stack-kotlin-spring@personal-claude-code
/plugin install stack-nextjs@personal-claude-code
```

## 첫 실행

```bash
/codex:setup       # codex CLI 인증 (openai/codex-plugin-cc, 한 번만)
/setup-team        # claude-team tmux 세션 + 페인 5개 + .claude-team/ 디렉터리 셋업
/feat <요청>        # 전체 11 단계 라이프사이클
# 또는
/task <요청>        # 작은 작업 (1–2 파일, 단일 영역)
```

`/setup-team` 은 `claude-team` 이라는 새 tmux 세션에 페인 5 개를 만들고 각 워커에 백그라운드 `claude` 를 띄운다. 다른 터미널에서 `tmux attach -t claude-team` 으로 진행 상황 확인 가능.

## 어떻게 작동하나

```
사용자 요청
    ↓
Technoking (main 페인, Tech Lead)
    ├─ 복잡도 판정 (small / medium / large)
    ├─ Spec Shaman → PRD 작성 (medium·large 만)
    ├─ Galaxy Brain → 설계 문서 + ADR (medium·large 만)
    ├─ 작업 분해 → ticket 발행
    │
    ▼ 워커 페인들이 폴링으로 ticket 픽업
Paladin (worker-be) · Wizard (worker-fe) · Witch (worker-qa)
    ├─ 각자 별도 git worktree 에서 병렬 구현
    ├─ 같은 에러 2 번 반복 (error_2x) → Technoking 이 codex 에 자동 위임 (rescue)
    └─ PR push 후 완료 알림
        ↓
Roastmaster (worker-review, 코드 리뷰어)
    ├─ codex 에 어드버서리얼 리뷰를 백그라운드로 보냄
    ├─ 결과 판정: APPROVE / COMMENT / BLOCKING
    └─ 같은 BLOCKING 이 2 라운드 반복 (pattern_stuck) → Technoking 이 codex 에 자동 위임 (rescue)
        ↓
Technoking → 머지 → 보고
```

워커들은 서로 직접 통신하지 않는다. **모든 조율은 `.claude-team/` 디렉터리의 파일** (ticket · inbox · review report) 로만 이뤄진다. 데이터 모델 전체는 [`workflows/skills/ticket-protocol/SKILL.md`](workflows/skills/ticket-protocol/SKILL.md).

### 워커는 어떻게 동작하나 — 2 단계 launch

워커 페인은 평소 shell 이 30 초마다 ticket 큐를 폴링한다 (claude 없음). ticket 이 떨어지면 그 자리에서 claude 가 발화하고, 작업이 끝나면 claude 는 종료되며 shell 이 폴링으로 복귀한다. 매 ticket 마다 fresh claude 세션.

```
[idle]               shell 폴링 (claude 없음)
    ↓ ticket-poll.sh 가 큐에서 자기 SLUG 매칭되는 ticket 발견
[claim]              queue/ → in-progress/ 로 atomic mv, owner 갱신
    ↓
[claude 발화]         shell 이 claude 를 백그라운드로 exec
    ↓                "T-NNNN 처리. 끝나면 touch <sentinel>" 첫 메시지
[작업]                claude 가 CLAUDE.md + 페르소나 + 스킬 로드 → 워크트리에서 구현 → PR push
    ↓                마지막 Bash: touch .claude-team/.runtime/<pane>.complete
[watchdog]            shell 이 sentinel 감지 → claude 종료
    ↓
[idle 복귀]           다음 ticket 까지 다시 shell 폴링
```

자세한 launch 메커니즘 (sentinel 파일, watchdog, CLI flags) 은 [`workflows/skills/tmux-worker-protocol/SKILL.md`](workflows/skills/tmux-worker-protocol/SKILL.md) 의 § Headless launch 참조.

## 디렉터리 구조

```
personal-claude-code/
├── .claude-plugin/marketplace.json   # 마켓플레이스 매니페스트
├── workflows/                        # 코어 플러그인 (필수)
│   ├── agents/                       # 7 페르소나 정의
│   ├── skills/                       # 스택 무관 스킬 8 개
│   ├── commands/                     # 슬래시 커맨드 12 개
│   ├── bin/                          # tmux / ticket 셸 스크립트
│   └── hooks/                        # 안전 가드 (위험 명령 차단)
├── stacks/                           # 스택별 플러그인 (옵션)
│   ├── kotlin-spring/                # Kotlin + Spring Boot
│   └── nextjs/                       # Next.js + TypeScript
├── docs/                             # 사용자 문서
├── CLAUDE.md                         # 글로벌 정책 (Claude 가 항상 읽음)
└── LICENSE                           # MIT
```

## 들어있는 것

이 마켓플레이스는 **3 개 플러그인** 으로 나뉜다. `workflows` 가 코어(필수), `stacks/` 아래 두 개는 프로젝트 스택에 맞춰 골라 깐다.

| 플러그인 | 종류 | 역할 |
|---|---|---|
| `workflows` | 코어 (필수) | 7 페르소나, 8 스킬, 12 슬래시 커맨드, tmux/ticket 스크립트, 안전 훅 |
| `stack-kotlin-spring` | 스택 (옵션) | Kotlin · Spring Boot 코딩·데이터 접근·테스트 규약 — [README](stacks/kotlin-spring/README.md) |
| `stack-nextjs` | 스택 (옵션) | Next.js · TypeScript 코딩·데이터·테스트 규약 — [README](stacks/nextjs/README.md) |

### `workflows` — 스택 무관 코어

페르소나, 11 단계 라이프사이클, ticket 프로토콜, `codex` 게이트가 모두 여기 있다. 어떤 언어/프레임워크 프로젝트든 이 플러그인 하나면 7 인 팀 운영이 가능. 코딩 시 워커들은 `coding-principles` / `testing-principles` 같은 **스택 무관** 원칙을 적용한다.

### `stacks/*` — 스택별 스킬 묶음

스택 플러그인은 그 스택만의 추가 스킬을 얹는 레이어다. 예를 들어 `stack-kotlin-spring` 은 워커에게 다음을 추가로 가르친다:

- 코루틴 안에서 `@Transactional` 컨텍스트가 누수되는 흔한 함정
- JPA 엔티티에서 `data class` 를 쓰면 안 되는 이유 (Hibernate 와 충돌)
- Flyway 마이그레이션은 `outOfOrder=false` 로 강제
- Spring 6 이후 `JdbcTemplate` 대신 `JdbcClient` 권장

`stack-nextjs` 도 Server Components, Server Actions, HydrationBoundary 같은 Next.js 고유 패턴을 같은 방식으로 다룬다.

**버전 핀 없음.** 스킬의 권장값은 작성 시점 스냅샷일 뿐이고, 실제 적용 시점에 워커가 프로젝트의 `build.gradle.kts` / `package.json` 을 직접 읽는다. 학습 데이터에 없는 새 버전이면 공식 문서를 검색해 검증한다 (detect-and-verify 프로토콜).

### 다른 언어로 커스텀

내가 쓰는 스택(Go · Python · Rust · Swift 등) 에 맞는 `stack-*` 플러그인을 직접 만들 수 있다. 권장 골격:

```
stacks/<name>/
├── .claude-plugin/plugin.json        # name, version, description, license
├── skills/
│   ├── <name>-core/SKILL.md          # 언어/프레임워크 컨벤션
│   ├── data-access/SKILL.md          # (백엔드라면) ORM/마이그레이션 규약
│   └── testing-<name>/SKILL.md       # 테스트 프레임워크 규약
└── hooks/
    └── stop-verification.sh          # 워커 turn 끝날 때 빌드/테스트 자동 검증
```

`stacks/kotlin-spring/` 또는 `stacks/nextjs/` 를 복사해 출발점으로 삼는 게 가장 빠르다. 마켓플레이스의 `marketplace.json` 에 plugin entry 를 추가한 뒤 `/plugin install` 로 사용.

## 7 인 팀

| 이름 | 직책 | 모델 | 페인 |
|---|---|---|---|
| **Technoking** | Tech Lead — 라이프사이클·작업 분배·머지 게이트 | **opus** | `main` |
| **Spec Shaman** | Product Owner — PRD 작성 | sonnet | subagent |
| **Galaxy Brain** | System Architect — 설계 문서 · ADR | **opus** | subagent |
| **Persistence Paladin** | Backend — DB · API · 서버 보안 | **opus** (effort: medium) | `worker-be` |
| **Pixel Wizard** | Frontend — UI · 접근성 · 프론트엔드 보안 | **opus** (effort: medium) | `worker-fe` |
| **What-If Witch** | QA — 인수 테스트 · 통합 · E2E | sonnet | `worker-qa` |
| **The Roastmaster** | Code Reviewer — codex 리뷰 디스패치 + 판정 | **opus** | `worker-review` |

자세한 카드: [`docs/personas.md`](docs/personas.md).

## 슬래시 커맨드 12 개

### 라이프사이클 (4)

| 커맨드 | 용도 | 언제 쓰나 |
|---|---|---|
| `/feat <요청>` | 전체 11 단계 (PRD → 설계 → 구현 → 리뷰 → 머지) | 신규 기능. medium·large 면 도중에 PRD/설계 확인 절차 있음 |
| `/design <요청>` | PRD + 설계 문서 + ADR 만 만들고 구현은 안 함 | 방향 검증·이해관계자 합의 단계에서 산출물만 필요할 때 |
| `/task <요청>` | 1–2 파일, 단일 영역의 짧은 변경 | 작은 버그 수정, 한 함수 리팩토링 |
| `/review <PR#·브랜치·범위>` | 이미 열린 PR · 브랜치 · 커밋 범위에 코드 리뷰 재실행 | 수동 수정 후 재리뷰, 외부에서 들어온 PR 감사 |

### 진단·운영 (4)

| 커맨드 | 용도 | 언제 쓰나 |
|---|---|---|
| `/diagnose <증상>` | 버그 조사 · 실패 경로 추적 · 수정 제안 (구현 X) | 원인을 모를 때 |
| `/setup-team` | `.claude-team/` 디렉터리 + tmux 페인 + 워커 부팅 | 최초 1 회 + 워커가 죽었을 때 재기동 |
| `/status` | 워커 페인 상태, ticket 큐, 진행 중 작업, 최근 완료 보드 | 지금 뭐가 돌고 있는지 한눈에 보고 싶을 때 |
| `/abort <T-NNNN>` | 진행 중 ticket 취소, 워커 정지, 워크트리 정리 | 잘못된 방향으로 가고 있을 때 중단 |

### 직렬화·확장 (4)

| 커맨드 | 용도 | 언제 쓰나 |
|---|---|---|
| `/handoff` | 현재 컨텍스트를 다음 세션용 ticket 으로 직렬화 | 컨텍스트가 차서 새 세션으로 넘어가야 할 때 |
| `/hire <역할>` | 커스텀 페르소나 추가 (예: DevOps · Data 전문가) | 기본 7 인 팀에 프로젝트 특화 역할이 필요할 때 |
| `/show-team` | 7 페르소나 + 모델 + 페인 + PID 로스터 출력 | 팀이 다 살아있는지 확인 |
| `/cleanup` | 오래된 ticket / review / rescue 아카이브, 고아 워크트리 제거 | 주기적 청소 |

## 핵심 정책

- **codex 는 필수 의존성** — `/codex:status` 가 ready 가 아니면 어떤 ticket 도 진행 안 됨. 약화된 모드 없음.
- **품질 게이트는 모든 변경에 동일하게 적용** — 작은 `/task` 도 codex 리뷰 + 자동 rescue 게이트 통과 의무.
- **자동 rescue** — 같은 에러가 2 번 반복되거나 같은 BLOCKING 이 2 라운드 이어지면 사용자 승인 없이 codex 에 위임해 패치를 받아온다. 워커 자체 감지를 놓쳤을 때를 위해 백그라운드 watchdog 이 40 초마다 6 가지 신호 (반복 에러·동일 줄·idle·last_update_at·worktree mtime·보호 파일 변경) 를 모아 검증한다 — **확정** 케이스만 자동 rescue / 에스컬레이션이 발동하고, **모호한** 케이스는 워커를 죽이지 않고 evidence 와 함께 사용자에게 결정을 묻는다.
- **보호 파일 (`protected_files`)** — Technoking 이 ticket 발행 시 "건드리면 안 되는" 글로브 목록 (계약 스냅샷·운영 yaml·lockfile·벤더 코드·서드파티 fixture 등) 을 지정할 수 있다. 워커는 그 파일들을 직접 편집할 수 없으며, 수정이 필요하면 곧장 에스컬레이션. watchdog 도 worktree diff 를 살펴 위반을 잡아낸다.
- **승인 절차 (Stop)** — `small` = 0 회 (자율 진행) / `medium` = 1 회 (PRD+설계 통합 확인) / `large` = 3 회 (PRD · 설계 · 작업 batch 각각). 머지 직전 추가 확인은 없음.
- **언어 정책** — 사용자가 직접 읽는 문서(PRD · 설계 · ADR · commit 본문 · PR 본문 · 리뷰 보고서) 는 **한국어**. 페르소나 정의 · 스킬 · 코드 · conventional commit prefix · YAML key 는 **영어**.

자세한 정책: [`CLAUDE.md`](CLAUDE.md).

## 더 알아보기

| 문서 | 내용 |
|---|---|
| [`docs/installation.md`](docs/installation.md) | 사전 조건 · 설치 · 첫 ticket · 트러블슈팅 |
| [`docs/personas.md`](docs/personas.md) | 7 페르소나 카드 (역할 · 도구 · 말투) |
| [`docs/ticket-protocol.md`](docs/ticket-protocol.md) | `.claude-team/` 구조와 수동 개입 방법 |
| [`docs/tmux-layout.md`](docs/tmux-layout.md) | 페인 레이아웃 · 모니터링 단축키 |
| [`docs/git-flow.md`](docs/git-flow.md) | 브랜치 · 커밋 · PR 컨벤션 |
| [`CLAUDE.md`](CLAUDE.md) | 글로벌 정책 (전 페르소나·스킬·커맨드에 적용) |
| [`workflows/skills/orchestration-guide/SKILL.md`](workflows/skills/orchestration-guide/SKILL.md) | 11 단계 라이프사이클 내부 동작 |
| [`workflows/skills/ticket-protocol/SKILL.md`](workflows/skills/ticket-protocol/SKILL.md) | ticket 7 종 schema + 상태 전이 |

## 라이선스

MIT — [`LICENSE`](LICENSE).
