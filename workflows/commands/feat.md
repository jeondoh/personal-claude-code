---
description: Start the full feature lifecycle (PRD → design → implement → review → merge). Technoking classifies complexity (small/medium/large) and routes through orchestration-guide's 11-step pipeline. Use this for any non-trivial feature; for 1–2 file changes, prefer /task.
---

# /feat — feature lifecycle entry point

This command hands the request to **Technoking**, who runs the full lifecycle defined in `orchestration-guide`. Quality gates (`/codex:adversarial-review` dispatched non-blockingly by Roastmaster + auto-rescue) apply at every complexity level — this command never lowers the bar.

## Pre-flight (gate every invocation)

1. `.claude-team/config.yml` exists. If not, halt: "run `/setup-team` first."
2. `/codex:status` returns ready. If not, halt: "run `/codex:setup` first."
3. All worker pane PIDs in `workers/registry.json` are alive. If any is dead, halt: "run `/setup-team` to re-launch panes."

If any check fails, do nothing else — surface the halt reason and stop.

## Behavior

Technoking takes the user prompt as the umbrella request and proceeds through the lifecycle in `orchestration-guide` (see § `/feat` 11-step lifecycle):

1. **Intake + complexity verdict.** Apply the rule table; honor auto-large triggers (auth/permission, DB schema, new domain, external integration). Record verdict on the umbrella ticket.
2. **PRD draft.** Dispatch Spec Shaman as a subagent. PRD body is **Korean**; frontmatter is English (see `documentation-criteria`).
3. **PRD approval Stop.** Large only. Use the Stop format from `orchestration-guide` § Stop format.
4. **Design + ADR + interfaces.** Dispatch Galaxy Brain as a subagent. ADR triggers per `documentation-criteria`.
5. **Design / merged-spec approval Stop.** Medium = merged PRD+Design Stop. Large = Design Stop.
6. **Task decomposition + ticket batch.** Use `ticket-protocol` § type=work. Large = batch approval Stop.
7. **Fail-first acceptance tests.** What-If Witch writes one test per AC; commits red. `untestable_ac` → escalate.
8. **Parallel implementation.** Paladin + Wizard work their assigned tickets in worktrees per `git-flow` and `tmux-worker-protocol`.
9. **PR + review loop.** Roastmaster dispatches `/codex:adversarial-review --background` per PR (non-blocking); codex is the sole reviewer, Roastmaster judges the returned findings. See `adversarial-review-bridge`. Max 3 BLOCKING rounds. Auto-rescue on `error_2x` or `pattern_stuck`.
10. **Integration + E2E.** Default for large; AC-driven for medium. Up to 2 retries.
11. **Merge + report.** Squash to main; ticket → `done`; worktree removed.

## Stops by complexity (B-pattern, shinpr-style)

| Complexity | Stops | Where |
|---|---:|---|
| small | 0 | (auto-routed to `/task`) |
| medium | 1 | step 5 (PRD+Design merged approval) |
| large | 3 | steps 3, 5, 6 |

After the last Stop, execution is autonomous through merge. The user may interrupt at any time.

## Forced escalations (Stop regardless)

- Worker emits `kind: escalation_needed` with `requirements_change | architectural_change | untestable_ac`.
- Mid-flight auto-escalation to large (e.g., new auth scope discovered).
- 3rd consecutive BLOCKING in step 9.
- Rescue validation fails (`reason: rescue_failed`).
- Mid-flight `codex_unavailable`.

## Delegation map

- Lifecycle mechanics → `orchestration-guide`
- Ticket schema and routing → `ticket-protocol`
- Pane delivery → `tmux-worker-protocol`
- Codex integration → `adversarial-review-bridge`
- Branch / commit / PR rules → `git-flow`
- Doc body rules → `documentation-criteria`
- Code quality → `coding-principles`
- Test rules → `testing-principles`
- Stack specifics → `stack-kotlin-spring/*` and `stack-nextjs/*` skills

## Expected output

- Umbrella ticket id (`T-NNNN`) and complexity verdict.
- For each Stop: a clear approval prompt per `orchestration-guide` § Stop format.
- For each PR: review report path (`RR-T-NNNN-<round>.md`) and verdict.
- Final merge: commit sha + completion summary.

If `complexity == small`, do not run `/feat` — re-route the user to `/task` with a one-line note.
