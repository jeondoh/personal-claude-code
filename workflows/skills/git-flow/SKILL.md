---
name: git-flow
description: Branching, commit, and PR conventions for the personal-claude-code workflows plugin. Use whenever a persona creates a branch, writes a commit, opens a PR, or merges. Applies to all personas; Technoking owns merge gating, Roastmaster owns the review bar (see adversarial-review-bridge for codex integration).
---

# Git Flow

Branch/commit/PR conventions for all tickets. Workers (Paladin, Wizard) work in **isolated worktrees** under `.worktrees/`; Technoking integrates and merges from `main`.

## Branches

### Naming

```
feat/T-NNNN-<slug>            # /feat ticket implementation
task/T-NNNN-<slug>            # small /task ticket
fix/T-NNNN-<slug>             # bug fix ticket
rescue/T-NNNN                 # codex-rescue patch (no slug — auto-generated)
review/RV-NNNN-<slug>         # rescue validation ticket
spike/T-NNNN-<slug>           # throwaway exploration (delete, never merge)
```

`<slug>`: kebab-case, ≤ 4 words, from ticket title.

### Worktrees

Every working ticket creates `.worktrees/T-NNNN/` off `main`; worker pane runs headless `claude` inside it. `.worktrees/` is gitignored. Created on `queue → in-progress`, removed on `in-progress → done`/`cancelled`. `/abort` and `/cleanup` handle orphans.

### Base branch

All work branches off `main` (default). No long-lived `develop`/release branches — merge freezes coordinated via Technoking, not git topology.

## Commits

### Atomic commits

One logical change per commit; any single commit must be revertable with the codebase still compiling. Own commit each for: behavior change / refactor (no behavior change) / test for an existing change / style-format (or automated CI commit).

A 200-line PR with 1 commit mixing refactor + feature + tests earns BLOCKING: "split commits."

### Message format (Conventional Commits)

```
<type>(<scope>): <subject — 한국어>

<body — 한국어>

<footer>
```

- **type** (English, fixed enum): `feat | fix | refactor | test | docs | chore | perf | build | ci`
- **scope** (English, optional): lowercase single word, module name (`auth`, `payments`, `ui`)
- **subject** (**Korean**): imperative, ≤ 72 chars (Korean char = 1), no trailing period
- **body** (**Korean**): WHY not WHAT, wrap ~80 columns, empty if subject self-explanatory
- **footer** (English keys): `Refs: T-0042`, `Closes: T-0042`, `Co-Authored-By: <name> <email>`

Every commit on a ticket branch references the ticket: `Refs: T-NNNN` (or `Closes:` for merge commit).

### Language policy

Subject + body **must be Korean** — user reads `git log` directly. English only for: `<type>`, `<scope>`, footer keys, ticket IDs, file paths, code symbols. **Never** English subject/body for a normal feature commit; exception only when the change is verbatim a foreign-language artifact (e.g., editing English docs). Same rule for PR title/body (see § Pull Requests).

### Example

```
feat(payments): 결제 엔드포인트에 멱등성 키 추가

클라이언트 재시도 요청이 ledger에 중복 항목을 만들던 문제 해결.
멱등성 키(클라이언트 발급 UUIDv4)를 payment_attempts에 저장,
24h 내 동일 키 재요청은 기존 결제 결과를 그대로 반환하도록 변경.

Refs: T-0118
```

### Forbidden

- `wip`, `fixup`, `temp`, `update` as subject — squash before pushing.
- `--no-verify` to skip pre-commit hooks (formatters, linters). On hook failure, fix the root cause.
- `--amend` on already-pushed commits without explicit user authorization.
- Force-push to `main` ever. Force-push to feature branch only when rewriting your own pushed history before a PR is opened for review.

## Pull Requests

### Title

`<type>(<scope>): <subject — 한국어>` — same format/language policy as commit subject, ≤ 72 chars (see § Commits / Language policy).

### Description (required sections, Korean body)

Section headers are Korean (user reads on GitHub). Technical enum tokens (e.g., `APPROVE`, `BLOCKING`, `AC-001`, `BL-0042`) stay English.

```markdown
## 요약
1–3개 불릿. 무엇이 어떻게 바뀌었는지·왜 (한 줄씩).

## 인수 기준 (Acceptance Criteria)
- [ ] AC-001: <PRD 인용>
- [ ] AC-002: ...

(small/no-PRD 티켓: `.claude-team/tickets/done/` 의 티켓 파일 링크)

## 테스트
- 단위 (Unit): <개수 또는 "n/a">
- 통합 (Integration): <개수 또는 "n/a">
- 인수 (Acceptance, What-If Witch): <개수 또는 "n/a">
- E2E: <개수 또는 "n/a">

## Codex 리뷰
- /codex:adversarial-review 실행: <yes/no, 링크 또는 result ID>
- verdict: <APPROVE | COMMENT | BLOCKING>
- 보고서: `.claude-team/reviews/RR-T-NNNN-<round>.md`

## 범위 외 (Out of scope, 별도 티켓)
- BL-NNNN: <한 줄 요약>
```

### Size

- Soft limit: **400 lines changed** (additions + deletions, excluding generated files, lockfiles, bulk-data test fixtures).
- Hard limit: **800 lines**. Over this earns BLOCKING: "split into smaller PRs." Galaxy Brain's task decomposition (`/feat` step 6) should prevent this; if not, that's a planning bug.
- Lockfile/generated-file diff is excluded from the size budget but must be in its own commit.

### Drafts

May open as draft for early feedback (don't request review while draft). Mark ready-for-review when: all AC checkboxes pass locally / all tests green / `/codex:adversarial-review` requested at least once.

## Review loop (cross-reference)

Step 9 of the 11-step lifecycle. Detailed in `orchestration-guide` and `adversarial-review-bridge`. Summary:

1. Technoking opens PR after worker reports completion.
2. Roastmaster reviews + invokes `/codex:adversarial-review`, writes `RR-T-NNNN-<round>.md`.
3. Verdict: `APPROVE` / `COMMENT` / `BLOCKING` (semantics in `orchestration-guide` step 9).
4. BLOCKING → fix in same branch, push, re-request review.
5. 2 consecutive BLOCKING with same `error_signature` → auto-rescue (see `adversarial-review-bridge`).
6. Max 3 review rounds before forced escalation.

## Merge

- **Strategy**: `--squash` only. Atomic commits during work, squashed at merge.
- **Squash message**: `<type>(<scope>): <subject>` from PR title + AC list in body + `Closes: T-NNNN`.
- Merge by Technoking only. Workers push to feature branch but never merge.
- Pre-merge checklist (Technoking enforces): all CI green, all AC checked, codex review attached, no unresolved BLOCKING.
- Post-merge: feature branch deleted, worktree removed, ticket transitions `in_review → done`.

## Cherry-pick / hotfix

Hotfix from `main` only. Branch: `fix/T-NNNN-<slug>` (same as normal fix). No special policy — same lifecycle and gates.

## When this skill conflicts with the AC

PR-size soft limit (400 lines) may be waived if Galaxy Brain's task decomposition explicitly justifies it (e.g., a generated migration file). Document the waiver in the PR description under `## Tests` as a `Waiver:` line. Hard limit (800 lines) is never waived without user approval.
