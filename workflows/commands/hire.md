---
description: Add a custom team member — create a new persona file under workflows/agents/ and register their pane (if any) in workers/registry.json. Use this to extend the default seven-persona team for a project-specific role (e.g., DevOps Druid, Data Diviner).
---

# /hire — add a new persona

The default team is seven personas (Technoking, Spec Shaman, Galaxy Brain, Persistence Paladin, Pixel Wizard, What-If Witch, The Roastmaster). `/hire` lets a user grow the roster for project-specific roles without forking the plugin.

## Pre-flight

1. `.claude-team/config.yml` exists.
2. `/codex:status` is ready.
3. The proposed `slug` does not collide with an existing file in `workflows/agents/` or with a reserved name (`technoking`, `spec-shaman`, `galaxy-brain`, `persistence-paladin`, `pixel-wizard`, `what-if-witch`, `the-roastmaster`).
4. If `pane` is requested, the target tmux pane id is free in `workers/registry.json` (no other persona currently bound).

Halt on any failure with the specific remediation.

## Behavior

Technoking collects the new persona spec from the user (single Stop, format below), then writes the persona file and updates the registry.

### Stop — gather persona spec

```
[Stop — /hire spec]

이번에 정하는 것: 신규 페르소나의 정체성과 페인 배치.

필요한 입력:
  - slug:           (소문자-하이픈, 예: devops-druid)
  - display name:   (예: DevOps Druid)
  - role:           (한 줄, 예: CI/CD pipelines and infra observability)
  - model:          opus | sonnet | haiku
  - effort:         (선택) low | medium | high | xhigh — worker 발화 시 `--effort` 로 전달
  - pane:           subagent | worker-<custom> (subagent 권장 — 신규 pane 은 tmux-setup.sh 수정 필요)
  - inherits:       기존 SKILL 이름들 (예: coding-principles, git-flow)
  - 영역 (한 줄):    이 페르소나만의 기여 영역

추천: subagent 페인. 기존 4 worker 페인 (be/fe/qa/review) 외 추가는 tmux-setup.sh 변경 부담.

승인하시면 작성합니다.
```

### Steps after approval

1. **Write persona file** at `workflows/agents/<slug>.md` with frontmatter (`name`, `description`, `model`, optional `pane`, optional `tools`) matching the seven default personas' shape.
2. **Body in English**, follows the structure of existing personas: identity, mandate, inputs/outputs, skills inherited, escalation rules, "When this skill conflicts with the AC" closer.
3. **Update `workers/registry.json`**:
   - Append to `panes` if a real pane is requested (with `persona`, `pane_id`, initial `pid: null`).
   - For subagent-only personas, no `panes` entry — just an entry in `team.subagents[]`.
4. **Optional pane launch** (only if a new tmux pane was requested): emit a one-line instruction to re-run `/setup-team` so the launcher script picks up the new pane. Do not attempt to mutate the live tmux session here.

## What this command never does

- Does not write code or scripts beyond the persona file and registry edit.
- Does not duplicate an existing persona's responsibilities — if the user's role overlaps, surface the conflict and ask before writing.
- Does not modify `tmux-setup.sh` or `worker-launch.sh`. New panes require a `/setup-team` re-run.

## Delegation map

- Persona file structure → existing files in `workflows/agents/` (use the closest analog as a template, e.g., a backend-flavored hire mirrors `persistence-paladin.md`).
- Registry schema → `ticket-protocol` § registry.json structure.
- Pane lifecycle → `tmux-worker-protocol`.

## Expected output

- Path of the new persona file.
- Updated `workers/registry.json` diff summary.
- Next-step note: "run `/show-team` to verify; if a new pane was added, run `/setup-team` to launch it."

## When this command conflicts with the AC

A new persona cannot bypass the codex hard dependency, the Roastmaster review loop, or any Stop policy. New personas inherit the workflow contract — `/hire` only adds capacity, not exemptions.
