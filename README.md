# personal-claude-code

> Claude Code 를 **회사처럼 굴러가는 7인 페르소나 팀** 으로 운영하는 마켓플레이스 플러그인.

Technoking 이 요청을 받아 복잡도(small/medium/large)를 판정하고, tmux 페인에서 병렬로 도는 헤드리스 `claude` 워커들에게 ticket 을 분배한다. 모든 PR 은 codex 어드버서리얼 리뷰를 통과해야 머지된다.

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

## 들어있는 것

| 플러그인 | 역할 |
|---|---|
| `workflows` | 코어 — 7 페르소나, 8 스킬, 12 슬래시 커맨드, tmux/ticket 스크립트, 훅 |
| `stack-kotlin-spring` | 옵션 — Kotlin · Spring Boot 코딩·데이터·테스트 규약 |
| `stack-nextjs` | 옵션 — Next.js · TypeScript 코딩·데이터·테스트 규약 |

스택 플러그인은 **버전 핀 없음** — 프로젝트의 `build.gradle.kts` / `package.json` 을 워커가 직접 읽고, 학습 데이터에 없는 새 버전이면 공식 문서로 검증하는 detect-and-verify 프로토콜.

## 설치

```bash
/plugin marketplace add sideholic/personal-claude-code
/plugin install workflows@personal-claude-code

# 옵션 (스택 사용 시 골라 설치)
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
| **Persistence Paladin** | Backend — DB · 서버 보안 | sonnet | `worker-be` |
| **Pixel Wizard** | Frontend — UI · a11y · 프론트 보안 | sonnet | `worker-fe` |
| **What-If Witch** | QA — 인수·통합·E2E | sonnet | `worker-qa` |
| **The Roastmaster** | Code Reviewer — codex 디스패치 + verdict | **opus** | `worker-review` |

자세한 카드: [`docs/personas.md`](docs/personas.md).

## 핵심 정책

- **codex 는 HARD 의존성** — `/codex:status` 가 ready 가 아니면 어떤 ticket 도 진행 안 됨. degraded 모드 없음.
- **품질 게이트는 complexity 무관 전체 적용** — `/task` 도 codex 어드버서리얼 리뷰 + 자동 rescue 게이트 동일.
- **자동 rescue** — 같은 에러 2회 (`error_2x`) 또는 Roastmaster `pattern_stuck` 시 사용자 승인 없이 codex 에 위임.
- **사용자 산출물은 한국어, 그 외는 영어** — PRD · Design · ADR · commit body · PR body · review report = 한국어. 페르소나·스킬·코드·conventional commit prefix = 영어.

자세한 정책: [`CLAUDE.md`](CLAUDE.md) (globally pinned, 충돌 시 최우선).

## 요구사항

| 항목 | 버전·설명 |
|---|---|
| Claude Code | 최신 (CLI / 웹 / VS Code 중 하나) |
| tmux | ≥ 3.2 (pane title 지원) |
| codex CLI | `/codex:setup` 이 설치·인증까지 안내 |
| shell | bash 3.2+ / zsh — macOS 기본 bash 호환 |
| (백엔드 스택만) | JDK + Gradle |
| (프론트 스택만) | Node ≥ 20.11 + pnpm 9+ (`corepack enable pnpm`) |

## 더 알아보기

| 문서 | 내용 |
|---|---|
| [`docs/installation.md`](docs/installation.md) | 사전조건 · 설치 · 첫 ticket · 트러블슈팅 |
| [`docs/personas.md`](docs/personas.md) | 7 페르소나 카드 |
| [`docs/ticket-protocol.md`](docs/ticket-protocol.md) | `.claude-team/` 구조와 수동 개입 |
| [`docs/tmux-layout.md`](docs/tmux-layout.md) | 페인 레이아웃 · 모니터링 |
| [`docs/git-flow.md`](docs/git-flow.md) | 브랜치 · 커밋 · PR 컨벤션 |
| [`CLAUDE.md`](CLAUDE.md) | 글로벌 정책 (전 페르소나·스킬·커맨드 적용) |

## 라이선스

MIT.
