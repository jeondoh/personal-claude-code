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
rescues/   backlog/   handoff/   archive/    workers/
```
The `.runtime/` subdir is created on demand by `worker-launch.sh` — do not create it here.
See ticket-protocol § Directory Layout.

**Step 3 — Write `.claude-team/config.yml`** (skip if file already exists)
Persona keys use **hyphens** to match the agent filenames (`agents/spec-shaman.md` etc.).
```yaml
project_name: personal-claude
plugins: { workflows: true, stack-kotlin-spring: false, stack-nextjs: false }
personas:
  technoking:           { model: sonnet, pane: main }
  spec-shaman:          { model: sonnet, pane: subagent }
  galaxy-brain:         { model: opus,   pane: subagent }
  persistence-paladin:  { model: sonnet, pane: worker-be }
  pixel-wizard:         { model: sonnet, pane: worker-fe }
  what-if-witch:        { model: sonnet, pane: worker-qa }
  the-roastmaster:      { model: opus,   pane: worker-review }
```

**Step 4 — Initialize `workers/registry.json`** (skip if file exists with non-empty `panes`)
```json
{ "counters": { "T": 0, "RV": 0, "BL": 0 }, "panes": {} }
```

**Step 5 — Launch tmux session + claude in every pane**
Call `tmux-setup.sh` (plugin's `bin/` is in PATH — call by bare name, do NOT use `workflows/scripts/...` paths or create symlinks). The script:

- Creates the `claude-team` session **rooted at the user's current working directory** (`pwd` at /setup-team invocation time). All panes inherit this cwd.
- Splits 5 panes in this order: `main` (pane 0) → `worker-review` (pane 1) → `worker-fe` (pane 2) → `worker-be` (pane 3) → `worker-qa` (pane 4).
- Launches `claude --dangerously-skip-permissions` in **every pane** (including `main`) via `worker-launch.sh`.
  - `main` (Technoking) gets a short Korean welcome listing the common slash commands; user then types here.
  - Worker panes get a one-time persona greeting + enter a silent polling loop. No visible per-poll output.
- Writes each worker pane's `{persona, pid, pane_id}` into `workers/registry.json` keyed by pane name (`worker-be`, `worker-fe`, `worker-qa`, `worker-review`), atomically and lock-protected. `main` is NOT tracked — it's the user's pane and implicit.

Re-runs are idempotent: if `claude-team` already exists, the script prints an attach hint and exits.
See tmux-worker-protocol § Pane Layout and § Headless Launch.

If `tmux-setup.sh` is absent (e.g. plugin install glitch): emit `"WARNING: tmux-setup.sh not found. Dirs and registry initialized. Reinstall the workflows plugin and rerun /setup-team."` and stop after Step 4.

## Delegation

- **tmux-worker-protocol** — pane geometry, headless launch, PID capture
- **ticket-protocol** — directory naming, registry.json schema, atomic writes

## Expected Output

```
/setup-team complete (cwd: /path/to/your/project)

Pane            Persona              PID     Status
--------------  -------------------  ------  ------
main            technoking           12344   alive  (interactive, user-facing)
worker-review   the-roastmaster      12345   alive
worker-fe       pixel-wizard         12346   alive
worker-be       persistence-paladin  12347   alive
worker-qa       what-if-witch        12348   alive

Next: type a request in the main pane — e.g. /feat <request> or /task <request>
```

Scripts missing: `"WARNING: tmux-setup.sh not found. Dirs and registry initialized. Reinstall the workflows plugin and rerun /setup-team."`
