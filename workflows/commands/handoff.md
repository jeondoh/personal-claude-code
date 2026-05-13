---
description: Serialize current orchestrator context into a handoff ticket for the next session
---

# /handoff

Capture the full orchestrator state into a structured handoff document so the next Claude session can resume without information loss. Issue this as the **last action** before clearing context.

---

## Pre-flight

Verify all three gates in order. Halt on first failure.

1. `.claude-team/config.yml` exists → if not: **halt** — "run `/setup-team` first"
2. `/codex:status` reports ready → if not: **halt** — "run `/codex:setup` first"
3. Every pane PID in `workers/registry.json` is alive → if not: **halt** — "dead worker detected; check pane state before handoff"

---

## Execution

### Step 1 — Timestamp

Generate `<ts>` in KST ISO compact format: `YYYYMMDDTHHmmss+0900`  
Example: `20260511T014530+0900`

Output path: `.claude-team/handoff/HANDOFF-<ts>.md`

### Step 2 — Gather state

Technoking collects current state from:

- `.claude-team/tickets/in-progress/*.md` — active tickets
- `.claude-team/tickets/queue/*.md` — queued tickets
- `workers/registry.json` — pane assignments and PID snapshot
- `.claude-team/inbox/` — any unprocessed messages
- `.claude-team/rescues/` — any open rescue tickets

### Step 3 — Write handoff document

**Document language: 한국어** (user artifact — the user reads this directly).

Frontmatter (`ticket-protocol § type=handoff`):

```yaml
---
type: handoff
id: HANDOFF-<ts>
created_at: <KST ISO-8601>
created_by: Technoking
status: pending
---
```

Body sections (Korean):

**① 진행 중 티켓**  
Table: `| ID | 제목 | 담당자 | 상태 |` for each ticket in `in-progress/` and `queue/`.

**② 다음 진입점**  
Which stage, which sub-task, and which step to resume from. Be specific (e.g. "5단계 — /review 작성 중, Step 2까지 완료").

**③ 미해결 결정 사항**  
Any open questions or decisions that could not be resolved automatically. List only real blockers.

**④ 페인별 마지막 상태**  
Snapshot from `workers/registry.json`: pane slug, persona, PID, last known task.

**⑤ 외부 의존 변경 사항**  
e.g. codex re-auth needed, environment variable changes, expired tokens. "없음" if none.

**⑥ 다음 세션 시작 메시지 (예시)**  
Include the exact message the user should paste into the new session:

```
BUILD-PROGRESS.md 와 AUTONOMOUS-PLAN.md 읽고 자율주행 이어서 진행.
(HANDOFF-<ts>.md 참고)
```

See `documentation-criteria § handoff body convention` for section ordering detail.

### Step 4 — Post-handoff

After the file is written, Technoking **takes no further action**. Workers remain idle. The user is responsible for clearing context.

---

## Expected Output

```
[/handoff complete]
File    : .claude-team/handoff/HANDOFF-<ts>.md
Tickets : <N> in-progress, <M> queued
Next session start message:
  "BUILD-PROGRESS.md 와 AUTONOMOUS-PLAN.md 읽고 자율주행 이어서 진행. (HANDOFF-<ts>.md 참고)"
```

If halted at pre-flight, output the halt reason. Handoff can be re-issued after resolving the blocker.
