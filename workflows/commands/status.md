---
description: Show worker pane status, ticket queue, in-progress work, and recent completions
---

# /status

Six-section progress board. Read-only snapshot of all active work.

## Pre-flight

1. `.claude-team/config.yml` exists? If not → halt: "Run `/setup-team` first."
2. `/codex:status` ready? If not → halt: "Run `/codex:setup` first."
3. `workers/registry.json` pane PIDs alive? (checked in Section 1 below)

## Sections

**Section 1 — Pane status**
Read `workers/registry.json` → `panes`. For each worker pane:
- `kill -0 <pid>` → `alive` or `DEAD`
- Infer current ticket: glob `tickets/in-progress/T-*-*.md`, match filename to pane's persona slug in frontmatter `owner` field.

```
Pane           Persona              PID     Status  Ticket
-------------  -------------------  ------  ------  --------
worker-be      persistence-paladin  12345   alive   T-0003
worker-fe      pixel-wizard         12346   alive   —
worker-qa      what-if-witch        12347   DEAD    —
worker-review  the-roastmaster      12348   alive   RV-0001
```

**Section 2 — Ticket queue**
Glob `tickets/queue/*.md`. Count total. List first 5 by filename order:
`<id>  <title>  [<complexity>]  <assignee>`

**Section 3 — In-progress**
Glob `tickets/in-progress/*.md`. List all:
`<id>  <title>  owner:<pane>  started:<started_at>`

**Section 4 — Recent completions (last 10)**
Glob `tickets/done/*.md`, sort by mtime descending, show first 10:
`<id>  <title>  completed:<mtime>`

**Section 5 — Inbox unread**
Glob `inbox/INBOX-*.json`. Count files where `processed` field is absent or `false`.
Show: `Inbox: <N> unread message(s) for Technoking.`

**Section 6 — Blocking reviews**
Glob `reviews/RR-T-*.md`. Filter where frontmatter `verdict: BLOCKING`.
List: `<review-id>  <ticket-id>  round:<N>  blocker:<summary>`

## Delegation

- **ticket-protocol** — directory layout, ticket frontmatter field names, ticket state machine

## Expected Output

Six sections rendered in ≤ 30 lines total. Example condensed form:

```
=== Pane Status ===
worker-be alive T-0003 | worker-fe alive — | worker-qa DEAD — | worker-review alive RV-0001

=== Queue (3 total) ===
T-0004  Add OAuth login  [medium]  pixel-wizard
T-0005  Fix N+1 query    [small]   persistence-paladin

=== In-Progress (2) ===
T-0003  Implement user profile API  owner:worker-be  started:2026-05-11T09:00:00+09:00
RV-0001 Review T-0003 round 1      owner:worker-review

=== Done (last 3) ===
T-0001  Bootstrap DB schema  2026-05-10
T-0002  Add health endpoint  2026-05-10

=== Inbox: 0 unread ===

=== Blocking Reviews: 0 ===
```
