---
description: Run a Roastmaster review with /codex:adversarial-review on an existing PR or branch. Use this to re-review after manual fixes, audit a PR opened outside the lifecycle, or get a second-opinion review on a merged change.
---

# /review — on-demand review of a PR or branch

Invokes the same review machinery as step 9 of `/feat`, but against a target the user names (existing PR, branch, or commit range). Useful when:

- A PR was opened outside the workflow and needs a Roastmaster pass.
- A reviewer wants a fresh round after manually pushing fixes.
- A merged change is being audited retrospectively.

## Pre-flight

1. `.claude-team/config.yml` exists.
2. `/codex:status` is ready.
3. `worker-review` pane PID alive per `workers/registry.json`. If dead, halt: "Roastmaster pane down — run `/setup-team`."
4. Argument parses to a valid target: PR number (`#NNN` or URL), branch name, or commit range (`<base>..<head>`). If unparseable, halt with a usage hint.

## Behavior

1. **Resolve target.** Technoking turns the argument into a concrete branch and base ref. For PR numbers, fetch via `gh pr view`. Record `target_ref`, `base_ref`, `pr_number?` on a synthetic review ticket.
2. **Dispatch review ticket.** Create `RV-NNNN-<slug>.md` of `type: review` (일반 PR review sub-case, see `ticket-protocol § 4a`) and route to `worker-review`. Frontmatter fields: `assignee: worker-review`, `pr_number` (if applicable), `base_branch`, `round: 1`. The ticket carries the resolved refs and the source ("user-invoked /review", not part of a `/feat` lifecycle).
3. **Roastmaster dispatches codex (non-blocking)** per `adversarial-review-bridge` § "When Roastmaster invokes adversarial-review":
   - Invoke `/codex:adversarial-review --background` against `target_ref`. Capture `codex_job_id`.
   - Write placeholder `RR-T-NNNN-1.md` with `status: codex_pending`.
   - Return to queue — do not block. Process other reviews / pending jobs.
4. **Result arrival (later turn).** Roastmaster fetches `/codex:result <codex_job_id>`, translates findings (Korean body), judges (uphold / downgrade), finalizes the report with verdict.
5. **Verdict surfaced to user.** `APPROVE` / `COMMENT` / `BLOCKING`. Unlike step 9, `/review` does **not** auto-trigger fix loops or merges — the verdict is informational. The user decides next steps.

## What this command never does

- Does not merge, even on `APPROVE`.
- Does not push fixes, even on `BLOCKING`.
- Does not auto-rescue. (Auto-rescue belongs to the `/feat` review loop, where Technoking owns dispatch context.)
- Does not modify the target branch.
- Does not block on the codex job — invocation is non-blocking and the verdict surfaces on a later Roastmaster turn (poll via `/status` if needed).

## Delegation map

- Codex contract → `adversarial-review-bridge`
- Review report schema → `ticket-protocol` § type=review_report
- Body language for the report → `documentation-criteria` (Korean body, English frontmatter)

## Expected output

- Review ticket id (`RV-NNNN`), report path (`RR-T-NNNN-1.md`), `codex_job_id`, and initial status (`codex_pending`).
- On later result arrival: verdict line `APPROVE | COMMENT | BLOCKING` + one-line summary of the top finding (or "no findings" on `APPROVE`).
- For `BLOCKING`, a suggested follow-up: "address findings, then run `/review <same target>` again."

## When this command conflicts with the AC

`/review` cannot skip codex. If `/codex:status` is not ready, halt — there is no degraded review mode (per `adversarial-review-bridge`). If the user explicitly requests "review without codex," refuse and direct them to fix codex first.
