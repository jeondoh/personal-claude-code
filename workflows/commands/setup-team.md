---
description: Bootstrap .claude-team directory, tmux worker panes, and the codex hard-dependency gate
---

# /setup-team

Initializes team infrastructure. Run once before any other command.

## Pre-flight

Only one check applies (this command *creates* config.yml and registry.json):

**`/codex:status` ready?** — If not, halt:
> "codex is not ready. Run `/codex:setup` first, then retry `/setup-team`."

Codex is a HARD dependency; no degraded mode.

## Steps

**Step 1 — Verify codex gate**
Invoke `/codex:status`. Result not `ready` → emit halt message and stop.

**Step 2 — Create `.claude-team/` directory tree** (skip existing dirs)
```
tickets/{queue,in-progress,done,cancelled}   reviews/   inbox/
rescues/   backlog/   handoff/   archive/
```
See ticket-protocol § Directory Layout.

**Step 3 — Write `.claude-team/config.yml`** (skip if file already exists)
```yaml
project_name: personal-claude
plugins: { workflows: true, stack_kotlin_spring: false, stack_nextjs: false }
personas:
  technoking:          { model: sonnet, pane: main }
  spec_shaman:         { model: sonnet, pane: subagent }
  galaxy_brain:        { model: opus,   pane: subagent }
  persistence_paladin: { model: sonnet, pane: worker-be }
  pixel_wizard:        { model: sonnet, pane: worker-fe }
  what_if_witch:       { model: sonnet, pane: worker-qa }
  the_roastmaster:     { model: opus,   pane: worker-review }
```

**Step 4 — Initialize `workers/registry.json`** (skip if panes non-empty)
```json
{ "counters": { "T": 0, "RV": 0, "BL": 0 }, "panes": {} }
```

**Step 5 — Launch tmux worker panes**
Call `workflows/scripts/tmux-setup.sh` → 4 panes: `worker-be`, `worker-fe`, `worker-qa`, `worker-review`.
See tmux-worker-protocol § Pane Layout.
If script absent (stage 6 not yet complete): log warning, skip steps 5–7, advise rerun after stage 6.

**Step 6 — Attach personas to panes**
For each worker pane: `workflows/scripts/worker-launch.sh <pane-id> <persona-slug>`.
See tmux-worker-protocol § Headless Launch for CLI flags and VERIFY marker.

**Step 7 — Update `workers/registry.json` panes**
Record `{ pid, pane_id, persona }` for each launched pane. Atomic write (temp → mv).
See ticket-protocol § Counter Lock.

## Delegation

- **tmux-worker-protocol** — pane geometry, headless launch, PID capture
- **ticket-protocol** — directory naming, registry.json schema, atomic writes

## Expected Output

```
/setup-team complete

Pane           Persona              PID     Status
-------------  -------------------  ------  ------
worker-be      persistence-paladin  12345   alive
worker-fe      pixel-wizard         12346   alive
worker-qa      what-if-witch        12347   alive
worker-review  the-roastmaster      12348   alive

Next: /show-team  or  /feat <request>
```

Scripts missing: `"WARNING: tmux-setup.sh not found. Dirs and registry initialized. Rerun after stage 6."`
