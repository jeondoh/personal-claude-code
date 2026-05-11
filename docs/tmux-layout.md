# tmux 레이아웃 — 사용자 가이드

claude-team tmux 세션의 페인 구조, 이동 방법, 워커 모니터링 방법을 설명합니다.

---

## 레이아웃 그림

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

| 페인 | 페르소나 | 모델 | 역할 |
|---|---|---|---|
| `main` | Technoking | sonnet | 오케스트레이터 — 사용자가 슬래시 커맨드 입력하는 곳 |
| `worker-fe` | Pixel Wizard | sonnet | 프론트엔드 구현 |
| `worker-be` | Persistence Paladin | sonnet | 백엔드·DB 구현 |
| `worker-qa` | What-If Witch | sonnet | QA·인수 테스트 |
| `worker-review` | The Roastmaster | opus | 코드 리뷰 |

페인 없는 페르소나 (subagent 전용):
- **Spec Shaman** (sonnet) — PRD 작성
- **Galaxy Brain** (opus) — 설계·진단

---

## 첫 attach

```bash
tmux attach -t claude-team          # 기본 세션 이름
tmux attach -t <session-name>       # 이름 변경 시
```

---

## 페인 이동 단축키

tmux 기본 prefix `Ctrl-b`. 다른 prefix 는 본인 `.tmux.conf` 기준.

| 동작 | 키 |
|---|---|
| 페인 이동 (방향) | `prefix` + `←` / `→` / `↑` / `↓` |
| 다음 페인으로 | `prefix` + `o` |
| 페인 번호로 이동 | `prefix` + `q` → 번호 입력 |
| 페인 zoom (확대/축소) | `prefix` + `z` |
| 세션 detach | `prefix` + `d` |

```bash
# 세션 종료 (모든 워커 종료됨)
tmux kill-session -t claude-team
```

---

## 워커 모니터링

각 페인은 헤드리스 `claude` 인스턴스가 persona prompt 와 함께 실행 중입니다. **사용자가 worker-\* 페인에 직접 타이핑하는 것은 권장하지 않습니다** — Technoking 이 ticket 발행으로 동작을 유도합니다.

```bash
# 페인 zoom (해당 페인 이동 후): prefix + z  (재입력하면 원상복구)

# 출력 캡처 (스크롤 가능); 인덱스: 0=main 1=worker-fe 2=worker-be 3=worker-qa 4=worker-review
tmux capture-pane -t claude-team:team.1 -p | less

# 페인 PID 확인
tmux list-panes -t claude-team:team -F '#{pane_index} #{pane_title} #{pane_pid}'
```

---

## 세션이 없을 때

`/setup-team` 으로 재셋업. 기존 `.claude-team/` 과 ticket 파일은 보존됩니다 (idempotent).

---

## 여러 프로젝트 동시 운영

세션 이름을 다르게 지정하면 됩니다. `.claude-team/` 은 cwd 기준이므로 ticket 은 자동 분리됩니다.

```bash
/setup-team --session-name claude-team-A   # 프로젝트 A
/setup-team --session-name claude-team-B   # 프로젝트 B (다른 디렉터리에서)
```
