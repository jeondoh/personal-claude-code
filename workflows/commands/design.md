---
description: Generate PRD, Design Doc, and ADRs only — stop before implementation. Useful when scoping a feature, validating direction with stakeholders, or producing planning artifacts without committing engineering capacity.
---

# /design — planning-only slice of /feat

Runs steps 2–5 of the `/feat` lifecycle (`orchestration-guide`) and stops. No tickets are decomposed, no code is written, no PR is opened. Output is a set of approved planning documents under `docs/`.

## Pre-flight

Same as `/feat`:

1. `.claude-team/config.yml` exists.
2. `/codex:status` is ready.
3. Worker pane PIDs alive per `workers/registry.json`.

Halt with the corresponding remediation message on any failure.

## Behavior

Technoking accepts the request and runs:

1. **Complexity verdict.** Same rule table as `/feat`. If verdict is `small`, halt: "small work does not need a design pass — use `/task`."
2. **PRD draft.** Spec Shaman subagent writes PRD per `documentation-criteria`. Body **Korean**.
3. **PRD approval Stop.** Large only. (Medium merges PRD into the design Stop in step 5.)
4. **Design + ADR + interfaces.** Galaxy Brain subagent. ADR triggers per `documentation-criteria`. Interface contracts (typed signatures, request/response shapes, DB schema diffs) included in the design doc.
5. **Design / merged-spec approval Stop.** Medium = merged PRD+Design Stop; large = Design Stop. After approval, the command **returns** — it does not advance into step 6 ticket decomposition.

## What this command never does

- No `T-NNNN` work ticket is created (the umbrella ticket is recorded as `done` on approval, with `closed_reason: design_only`).
- No worker pane dispatch.
- No PR.
- No code edits.

If the user wants to proceed to implementation after design approval, they invoke `/feat` again with a follow-up prompt (Technoking detects the prior umbrella ticket and resumes from step 6 with batch decomposition).

## Delegation map

- Lifecycle → `orchestration-guide` (steps 2–5 only)
- PRD / Design / ADR body rules → `documentation-criteria`
- Stop format → `orchestration-guide` § Stop format

## Expected output

- Umbrella ticket id and complexity verdict.
- Final paths: `docs/prd/<slug>-prd.md`, `docs/design/<slug>-design.md`, optional `docs/adr/ADR-NNNN-*.md`.
- For each Stop: an approval prompt with recommendation and alternates per `orchestration-guide` § Stop format.
- After final approval: a one-line summary + a follow-up suggestion ("run `/feat <same prompt>` to proceed to ticket decomposition").

## When this command conflicts with the AC

`/design` cannot waive the Stop policy. If the user requests "skip the Stop and just write the docs," refuse — the Stop is the contract that lets the user steer scope before engineering cost lands. They can approve quickly, but the prompt is not optional.
