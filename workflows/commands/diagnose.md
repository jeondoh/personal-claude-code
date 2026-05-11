---
description: Investigate a bug, trace failure path, propose fixes — no implementation, just diagnosis
---

# /diagnose

Produce a structured diagnosis document. No code is written or committed. Implementation requires a separate `/task` or `/feat` invocation.

---

## Pre-flight

Verify all three gates in order. Halt on first failure.

1. `.claude-team/config.yml` exists → if not: **halt** — "run `/setup-team` first"
2. `/codex:status` reports ready → if not: **halt** — "run `/codex:setup` first"
3. Every pane PID in `workers/registry.json` is alive → if not: **halt** — "dead worker detected; run `/setup-team` to restart panes"

---

## Execution

### Step 1 — Input collection (Technoking)

Technoking collects and normalises the bug report. Required fields (prompt user if missing):

| Field | Description |
|-------|-------------|
| `symptom` | What the user observed (error message, wrong output, crash) |
| `repro` | Minimal reproduction steps |
| `suspected_area` | File path(s) or module(s) the user suspects (optional) |
| `environment` | Stack, version, env (optional but helpful) |

### Step 2 — Dispatch decision

- **Trivial** (single obvious call site, no cross-module tracing needed): Technoking performs direct triage inline. Skip Galaxy Brain dispatch.
- **Non-trivial** (cross-module, async flow, infra, data corruption, race condition): Technoking dispatches Galaxy Brain subagent with the normalised input from Step 1.

Galaxy Brain operates per `documentation-criteria § Diagnose section`.

### Step 3 — Diagnosis document

Galaxy Brain (or Technoking for trivial) writes:

```
docs/diagnose/<slug>-diagnose.md
```

Where `<slug>` is `kebab-case` of the symptom summary + KST date (e.g. `login-500-20260511`).

**Document language: Korean** (user artifact — see language policy).

Document sections follow `documentation-criteria § Diagnose section`:
- 증상 요약
- 재현 절차
- 실패 경로 추적 (call stack / data flow)
- 근본 원인 (root cause)
- 영향 범위
- 수정 제안 (구현 X, 방향만)

### Step 4 — Fix routing

After the document is written, Technoking outputs a one-line root cause summary and a routing recommendation:

- Estimated 1–2 file change, no DB/auth → recommend `/task`
- Larger scope → recommend `/feat`
- Unclear scope → recommend user review the diagnose doc first, then decide

Technoking does **not** start implementation. The user must explicitly invoke `/task` or `/feat`.

---

## Expected Output

```
[/diagnose complete]
Document : docs/diagnose/<slug>-diagnose.md
Root cause (1-line): <English summary>
Recommended next  : /task "<fix title>" | /feat "<fix title>"
```

If halted at pre-flight, output the halt reason and the corrective command.
