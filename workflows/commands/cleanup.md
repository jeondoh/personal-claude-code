---
description: Archive stale tickets, reviews, and rescues; remove orphan worktrees; reclaim disk
---

# /cleanup

Maintenance command. Archives stale artifacts, purges processed inbox messages,
and surfaces orphan worktrees for user-confirmed removal.

## Pre-flight

1. `.claude-team/config.yml` exists? If not → halt: "Run `/setup-team` first."
2. `/codex:status` ready? If not → halt: "Run `/codex:setup` first."
3. `workers/registry.json` pane PIDs alive? Warn if any DEAD (do not halt — cleanup may proceed).

## Steps

**Step 1 — Archive done tickets (threshold: 30 days)**
Glob `tickets/done/*.md`. For each file where mtime > 30 days ago:
- Determine target: `archive/<YYYY-MM>/done/` where YYYY-MM is file's mtime month.
- Create target dir if needed, then `mv` file atomically.
- Accumulate count.

**Step 2 — Archive cancelled tickets (threshold: 7 days)**
Glob `tickets/cancelled/*.md`. For each file where mtime > 7 days ago:
- Move to `archive/<YYYY-MM>/cancelled/`.

**Step 3 — Archive merged review reports (threshold: 30 days post-merge)**
Glob `reviews/RR-*.md`. For each file where frontmatter `merged_at` is set
and `now − merged_at > 30 days`:
- Move to `archive/<YYYY-MM>/reviews/`.
If `merged_at` is absent, skip (review still open or pre-dates field).

**Step 4 — Archive stale rescues (threshold: 30 days)**
Glob `rescues/RESCUE-*.md`. For each file where mtime > 30 days ago:
- Move to `archive/<YYYY-MM>/rescues/`.

**Step 5 — Delete processed inbox messages (threshold: 1 day)**
Glob `inbox/INBOX-*.json`. For each file where mtime > 1 day ago
AND JSON field `processed` is `true`:
- Delete file (not archived — inbox is transient).

**Step 6 — Identify orphan worktrees**
Run `git worktree list --porcelain` to get all registered worktrees.
Collect ticket IDs from `tickets/in-progress/` filenames (`T-NNNN` prefix).
An orphan = a worktree whose branch name matches `ticket/T-NNNN` but `T-NNNN`
is NOT present in `in-progress/`.

List orphan candidates. **Do not remove automatically.**
Prompt: "Found <N> orphan worktree(s). Confirm removal? (yes/no)"
On confirmation: `git worktree remove --force <path>` for each.

**Step 7 — Report disk delta**
Capture disk usage of `.claude-team/` and `.worktrees/` before step 1 (`du -sh`),
then again after step 6. Report freed space.

## Delegation

- **ticket-protocol** — archive directory naming, mtime thresholds, ticket state machine

## Expected Output

```
/cleanup complete

Archived:
  done tickets:       <N>  (→ archive/<YYYY-MM>/done/)
  cancelled tickets:  <N>  (→ archive/<YYYY-MM>/cancelled/)
  review reports:     <N>  (→ archive/<YYYY-MM>/reviews/)
  rescues:            <N>  (→ archive/<YYYY-MM>/rescues/)

Deleted:
  processed inbox:    <N> file(s)

Orphan worktrees:     <N>  (user confirmed: removed <M>)

Disk: <before> → <after>  (freed <delta>)
```

Nothing to clean: `"Everything is tidy. Nothing to archive or remove."`
