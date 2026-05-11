---
name: git-flow
description: Branching, commit, and PR conventions for the personal-claude-code workflows plugin. Use whenever a persona creates a branch, writes a commit, opens a PR, or merges. Applies to all personas; Technoking owns merge gating, Roastmaster owns the review bar (see adversarial-review-bridge for codex integration).
---

# Git Flow

Conventions for branches, commits, and PRs across all tickets. Worker personas (Paladin, Wizard) work in **isolated worktrees** under `.worktrees/`; Technoking integrates and merges from `main`.

## Branches

### Naming

```
feat/T-NNNN-<slug>            # /feat ticket implementation
task/T-NNNN-<slug>            # small /task ticket
fix/T-NNNN-<slug>             # bug fix ticket
rescue/T-NNNN                 # codex-rescue patch (no slug — auto-generated)
review/RV-NNNN-<slug>         # rescue validation ticket
spike/T-NNNN-<slug>           # throwaway exploration (must be deleted, not merged)
```

`<slug>`: kebab-case, ≤ 4 words, derived from ticket title.

### Worktrees

Every working ticket creates `.worktrees/T-NNNN/` as a git worktree off `main`. Worker pane runs headless `claude` inside this directory. `.worktrees/` is gitignored.

Lifecycle: created when ticket transitions `queue → in-progress`, removed when ticket transitions `in-progress → done` or `cancelled`. `/abort` and `/cleanup` handle orphan removal.

### Base branch

All work branches off `main` (the default). No long-lived `develop` or release branches — merge freezes are coordinated via Technoking, not via git topology.

## Commits

### Atomic commits

One logical change per commit. Reviewer should be able to revert any single commit and have the codebase still compile.

- Behavior change → its own commit.
- Refactor → its own commit (no behavior change inside).
- Test addition for an existing change → its own commit.
- Style/format → its own commit (or an automated CI commit).

A 200-line PR with 1 commit that mixes refactor + feature + tests will earn BLOCKING from Roastmaster: "split commits."

### Message format (Conventional Commits)

```
<type>(<scope>): <subject>

<body>

<footer>
```

- **type**: `feat | fix | refactor | test | docs | chore | perf | build | ci`
- **scope**: optional, lowercase, single word — typically a module name (`auth`, `payments`, `ui`)
- **subject**: imperative mood, ≤ 72 chars, no trailing period
- **body**: WHY, not WHAT. Wrap at 80 chars. Empty if subject is self-explanatory.
- **footer**: `Refs: T-0042`, `Closes: T-0042`, `Co-Authored-By: ...`

Every commit on a ticket branch must reference the ticket: `Refs: T-NNNN` (or `Closes:` for the merge commit).

### Examples

```
feat(payments): add idempotency key to charge endpoint

Charge requests retried by the client previously created duplicate
ledger entries. Idempotency key (UUIDv4 from client) is now stored
in `payment_attempts` and returned charges are deduped within 24h.

Refs: T-0118
```

```
fix(auth): reject expired refresh tokens at validation

Refs: T-0124
```

### Forbidden

- `wip`, `fixup`, `temp`, `update` as the subject — squash before pushing.
- `--no-verify` to skip pre-commit hooks (auto-formatters, linters). If a hook fails, fix the root cause.
- `--amend` on already-pushed commits without explicit user authorization.
- Force-push to `main` ever. Force-push to feature branch only when rewriting your own pushed history before a PR is opened for review.

## Pull Requests

### Title

`<type>(<scope>): <subject>` — same format as commit subject. ≤ 72 chars.

### Description (required sections)

```markdown
## Summary
1–3 bullets. What changed and why (one sentence each).

## Acceptance Criteria
- [ ] AC-001: <text from PRD>
- [ ] AC-002: ...

(small/no-PRD tickets: link the ticket file under `.claude-team/tickets/done/`)

## Tests
- Unit: <count or "n/a">
- Integration: <count or "n/a">
- Acceptance (What-If Witch): <count or "n/a">
- E2E: <count or "n/a">

## Codex review
- /codex:adversarial-review run: <yes/no, link or paste-of-result-id>

## Out of scope (filed)
- BL-NNNN: <one line>
```

### Size

- Soft limit: **400 lines changed** (additions + deletions, excluding generated files, lockfiles, test fixtures with bulk data).
- Hard limit: **800 lines**. PR over this earns BLOCKING from Roastmaster: "split into smaller PRs." Galaxy Brain's task decomposition (step 6 of `/feat`) should prevent this; if it didn't, that's a planning bug.
- Lockfile / generated-file diff is excluded from the size budget but must be in its own commit.

### Drafts

PRs may be opened as draft for early feedback. Do not request review while in draft. Mark ready-for-review when:

- All AC checkboxes pass locally
- All tests green
- `/codex:adversarial-review` has been requested at least once

## Review loop (cross-reference)

Step 9 of the 11-step lifecycle. Defined in detail in `orchestration-guide` and `adversarial-review-bridge`. Summary:

1. Technoking opens PR after worker reports completion.
2. Roastmaster reviews + invokes `/codex:adversarial-review`, writes `RR-T-NNNN-<round>.md`.
3. Verdict: `APPROVE` / `COMMENT` / `BLOCKING` (semantics in `orchestration-guide` step 9).
4. BLOCKING → fix in same branch, push, re-request review.
5. 2 consecutive BLOCKING with same `error_signature` → auto-rescue (see `adversarial-review-bridge`).
6. Max 3 review rounds before forced escalation.

## Merge

- **Strategy**: `--squash` only. Atomic commits during work, squashed at merge.
- **Squash message**: `<type>(<scope>): <subject>` from PR title + AC list in body + `Closes: T-NNNN`.
- Merge by Technoking only. Worker personas push to feature branch but never merge.
- Pre-merge checklist (Technoking enforces): all CI green, all AC checked, codex review attached, no unresolved BLOCKING.
- Post-merge: feature branch deleted, worktree removed, ticket transitions `in_review → done`.

## Cherry-pick / hotfix

Hotfix from `main` only. Branch name: `fix/T-NNNN-<slug>` (same as normal fix). No special policy — hotfixes follow the same lifecycle and gates.

## When this skill conflicts with the AC

PR-size soft limit (400 lines) may be waived if Galaxy Brain's task decomposition explicitly justifies it (e.g., a generated migration file). Document the waiver in the PR description under `## Tests` as a `Waiver:` line. Hard limit (800 lines) is never waived without user approval.
