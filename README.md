# personal-claude-code

회사처럼 굴러가는 **7명 페르소나 + tmux 페인 병렬 워커 + codex 어드버서리얼 리뷰**의 개인용 Claude Code 마켓플레이스.

Technoking (Tech Lead) 이 요청을 받아 복잡도를 판정하고, 적절한 페르소나에게 ticket 을 분배하며, tmux 페인의 헤드리스 `claude` 인스턴스가 병렬로 처리한다. 모든 PR 은 Roastmaster 의 리뷰 + `/codex:adversarial-review` 를 통과해야 머지된다.

## 무엇이 들어있나

| 플러그인 | 설명 |
|---|---|
| `workflows` | 코어 — 7 페르소나, 8 스킬, 12 커맨드, tmux·ticket 스크립트, 훅 |
| `stack-kotlin-spring` | 옵션 — JDK 24 / Kotlin 2.2 / Spring Boot 4 / Gradle Kotlin DSL 스택 |
| `stack-nextjs` | 옵션 — Next.js 15 / React 19 / TypeScript 5 / pnpm 9 / TanStack Query v5 스택 |

## 설치

```
/plugin marketplace add sideholic/personal-claude-code
/plugin install workflows@personal-claude-code
/plugin install stack-kotlin-spring@personal-claude-code   # 옵션 (백엔드)
/plugin install stack-nextjs@personal-claude-code           # 옵션 (프론트)
```

설치 후 `/plugin list` 로 플러그인이 로드됐는지 확인.

## 첫 실행

```
1) /codex:setup        # codex CLI 인증 (openai/codex-plugin-cc)
2) /setup-team         # tmux 페인 + .claude-team/ 디렉터리 셋업
3) /feat <요청>         # 전체 11단계 라이프사이클 시작
   또는
   /task <요청>         # small 작업 (1–2 파일, 단일 영역)
```

## 팀 구성

Technoking (sonnet, main) · Spec Shaman (sonnet, subagent) · Galaxy Brain (**opus**, subagent) · Persistence Paladin (sonnet, worker-be) · Pixel Wizard (sonnet, worker-fe) · What-If Witch (sonnet, worker-qa) · The Roastmaster (**opus**, worker-review).

자세한 역할은 [`docs/personas.md`](docs/personas.md) 참고.

## 요구사항

- **Node ≥ 20.11** (stack-nextjs 의 pnpm 9 / Next.js 15 요구)
- **tmux ≥ 3.2** (pane title 지원)
- **codex CLI + 인증** (`/codex:setup` 이 설치까지 안내)
- **Claude Code** (CLI / 웹 / VS Code 중 하나, Mac/Linux 권장)
- JDK 24 + Gradle — `stack-kotlin-spring` 사용 시
- pnpm 9+ — `stack-nextjs` 사용 시 (`corepack enable pnpm`)

## 더 알아보기

| 문서 | 내용 |
|---|---|
| [`docs/installation.md`](docs/installation.md) | 사전조건 → 설치 → 첫 ticket 상세 가이드 + 트러블슈팅 |
| [`CLAUDE.md`](CLAUDE.md) | 정책·컨벤션 (Claude 가 항상 읽는 글로벌 가이드) |
| [`docs/personas.md`](docs/personas.md) | 7명 페르소나 카드 |
| [`docs/ticket-protocol.md`](docs/ticket-protocol.md) | `.claude-team/` 구조, ticket 상태 관찰, 수동 개입 |
| [`docs/tmux-layout.md`](docs/tmux-layout.md) | 페인 그림 + 이동 단축키 + 워커 모니터링 |
| [`docs/git-flow.md`](docs/git-flow.md) | 브랜치/커밋/PR 관찰 + hotfix |

## 라이선스

<!-- TODO: 라이선스 결정 후 업데이트. 현재 미설정. -->
MIT (예정)

---

이 README 는 entry-point. 정책·컨벤션은 `CLAUDE.md`, 운영 디테일은 `docs/` 하위 파일.
