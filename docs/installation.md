# 설치 가이드

이 문서는 `personal-claude-code` 를 처음 설치하고 첫 번째 ticket 을 돌리기까지의 전 과정을 안내한다.

---

## 사전 조건

| 도구 | 버전 | 이유 |
|---|---|---|
| **Node.js** | ≥ 20.11 | `stack-nextjs` 의 pnpm 9 / Next.js 15 런타임 요구 |
| **tmux** | ≥ 3.2 | pane title 지원 (워커 식별에 사용) |
| **codex CLI** | 최신 | `/codex:setup` 이 설치·인증 안내 — 미리 없어도 OK |
| **Claude Code** | 최신 | CLI / 웹 / VS Code 중 하나. Mac/Linux 권장 |
| JDK 24 + Gradle | 백엔드만 | `stack-kotlin-spring` 핀 버전 — Kotlin 2.2 / Spring Boot 4 |
| pnpm 9+ | 프론트만 | `corepack enable pnpm` 으로 활성화 |

```bash
node -v && tmux -V   # 버전 확인
```

---

## 1단계 — codex 설정

`codex-plugin-cc` 는 모든 ticket 의 리뷰·rescue 게이트를 담당하는 **HARD 의존성**이다. 이것이 준비되지 않으면 어떤 커맨드도 진행되지 않는다.

```
/codex:setup
```

`/codex:setup` 이 codex CLI 설치, 인증(API 키), 플러그인 연결까지 안내한다. 완료 후 상태 확인:

```
/codex:status
```

`ready` 가 출력되면 다음 단계로 진행한다. `not ready` 라면 아래 트러블슈팅 섹션을 참고.

---

## 2단계 — 마켓 추가 + 플러그인 설치

```
/plugin marketplace add sideholic/personal-claude-code
/plugin install workflows@personal-claude-code
/plugin install stack-kotlin-spring@personal-claude-code   # 옵션 (백엔드)
/plugin install stack-nextjs@personal-claude-code           # 옵션 (프론트)
```

설치 확인:

```
/plugin list
```

`workflows@personal-claude-code` 가 목록에 보이면 정상. 선택한 스택 플러그인도 함께 확인한다.

---

## 3단계 — /setup-team 실행

```
/setup-team
```

이 명령이 하는 일:

1. `.claude-team/` 디렉터리 트리 생성 (`tickets/`, `reviews/`, `inbox/`, `rescues/` 등)
2. `.claude-team/config.yml` 작성 (페르소나 모델 배정 기록)
3. `workers/registry.json` 초기화 (counter: T=0, RV=0, BL=0)
4. `tmux-setup.sh` 호출 (플러그인 `bin/` 이 PATH 에 자동 추가됨 — bare name 으로 호출, 심볼릭 링크 만들지 말 것) → 4개 워커 페인 생성
   - `worker-be` (Persistence Paladin), `worker-fe` (Pixel Wizard)
   - `worker-qa` (What-If Witch), `worker-review` (The Roastmaster)
5. 각 페인에 `worker-launch.sh` 로 헤드리스 `claude` + 페르소나 부착

완료되면 페인 PID 표 + `Next: /show-team or /feat <request>` 출력. 팀 로스터 확인:

```
/show-team
```

모든 페인이 `alive` 여야 한다.

---

## 4단계 — 첫 작업

```
/feat "hello world endpoint"
```

Technoking 이 복잡도를 판정한다: small (1–2 파일) → Stop 0회, medium → Stop 1회, large → Stop 3회. 복잡도와 무관하게 모든 PR 에 Roastmaster 리뷰 + `/codex:adversarial-review` + 자동 rescue 가 적용된다.

진행 상황 확인:

```
/status
```

---

## 샘플 `.claude/settings.local.json`

hooks 를 수동 등록하려면 아래 설정을 `.claude/settings.local.json` 에 머지한다.

```jsonc
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [{
          "type": "command",
          "command": "$CLAUDE_PROJECT_DIR/workflows/hooks/block-dangerous.sh"
        }]
      }
    ],
    "Stop": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/stack-kotlin-spring/hooks/stop-verification.sh"
          },
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/stack-nextjs/hooks/stop-verification.sh"
          }
        ]
      }
    ]
  }
}
```

두 stop hook 을 모두 등록해도 자기 스택이 아니면 자동으로 skip (`exit 0`) 한다. 일시 비활성화:

```bash
CLAUDE_TEAM_SKIP_VERIFY=1 claude ...
```

---

## 트러블슈팅

| 증상 | 해결 |
|---|---|
| `/codex:status` fails | `/codex:setup` 재실행. rate limit 이면 잠시 대기. API 키·경로 환경변수 확인. |
| `worker-launch.sh: claude --print not found` | `claude --help` 로 실제 flag 확인 후 `worker-launch.sh` L107 VERIFY 마커 수정. 9단계 스모크 테스트에서 공식 검증. |
| tmux 세션 충돌 | `tmux kill-session -t claude-team` 후 `/setup-team` 재실행. |
| `.claude-team/.counter.lock` 락 충돌 | `rmdir .claude-team/.counter.lock` 후 재시도. 락이 오래됐을 때 발생. |
| stop-verification 이 매 turn 빌드 — 너무 느림 | `CLAUDE_TEAM_SKIP_VERIFY=1` 으로 임시 비활성화. |
| `/show-team` 에서 pane DEAD | `/setup-team` 재실행으로 해당 페인 재기동. |

---

## 다음 단계

| 문서 | 내용 |
|---|---|
| [`docs/personas.md`](personas.md) | 7명 페르소나 역할·모델·페인 상세 |
| [`docs/ticket-protocol.md`](ticket-protocol.md) | `.claude-team/` 구조, ticket 상태 관찰, 수동 개입 방법 |
| [`docs/tmux-layout.md`](tmux-layout.md) | 페인 레이아웃 그림, 이동 단축키, 워커 모니터링 |
| [`docs/git-flow.md`](git-flow.md) | 브랜치/커밋/PR 관찰, hotfix 절차 |
