---
description: Display the team roster — personas, models, panes, and current PID status
---

# /show-team

Read-only roster view. Shows all 7 personas, their models, pane assignments, and live PID status.

## Pre-flight

1. `.claude-team/config.yml` exists? If not → halt: "Run `/setup-team` first."
2. `/codex:status` ready? If not → halt: "Run `/codex:setup` first."
3. `workers/registry.json` pane PIDs alive? (checked in Step 2 below)

## Steps

**Step 1 — Parse persona frontmatter**
Glob `workflows/agents/*.md`. For each file, read YAML frontmatter fields:
`name`, `description`, `model`, `pane` (use `subagent` if field absent).
Build an in-memory list ordered by persona index (1–7).

**Step 2 — Check pane liveness**
Read `workers/registry.json` → `panes` map.
For each entry with a real pane (not `subagent`), check `kill -0 <pid>` (exit 0 = alive).
Mark result as `alive` or `DEAD`.
Personas with `pane: subagent` always show `—` in the PID column.

**Step 3 — Render table**
```
#  Persona               Role                   Model   Pane           PID
-  --------------------  ---------------------  ------  -------------  ------
1  Technoking            Tech Lead              opus    main           <pid>
2  Spec Shaman           Product Owner          sonnet  subagent       —
3  Galaxy Brain          System Architect       opus    subagent       —
4  Persistence Paladin   Backend / DB / Sec     opus    worker-be      <pid>
5  Pixel Wizard          Frontend / a11y        opus    worker-fe      <pid>
6  What-If Witch         QA                     sonnet  worker-qa      <pid>
7  The Roastmaster       Code Reviewer          opus    worker-review  <pid>
```

## Delegation

Direct read-only operation — no skill delegation required.
Refer to ticket-protocol § registry.json Schema for field names.

## Expected Output

Table as above, followed by a one-line summary:

- All alive: `"All 4 worker panes alive. Team ready."`
- Any dead: `"worker-be DEAD — restart via /setup-team."`

If `/setup-team` has never been run (registry panes empty):
```
No worker panes registered. Run /setup-team to bootstrap the team.
```
