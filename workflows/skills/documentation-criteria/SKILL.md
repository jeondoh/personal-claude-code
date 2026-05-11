---
name: documentation-criteria
description: Criteria for PRD, Design Doc, ADR, and Diagnose documents — when to create them, what each must contain, where they live, how they get approved. Use when a persona creates or reviews a user-facing artifact (Spec Shaman, Galaxy Brain, Roastmaster's doc-quality bar). Excludes tickets (see ticket-protocol) and review reports (see adversarial-review-bridge).
---

# Documentation Criteria

User-facing artifacts: **PRD**, **Design Doc**, **ADR**, **Diagnose**. These are tracked in `docs/*` (git-tracked) and consumed by humans + future personas across sessions.

Internal workflow files (tickets, reviews, inbox, handoff) live under `.claude-team/` (gitignored) and follow `ticket-protocol`, not this skill.

## Language and metadata policy

- **Body**: Korean (user-consumed artifacts).
- **Frontmatter** (YAML keys + enum values): English (programmatic parsing).
- **Identifiers** (file names, AC IDs, ADR numbers): English.
- **Diagrams**: Mermaid. Labels in body language (Korean).

Frontmatter on every doc:

```yaml
---
type: prd | design | adr | diagnose
id: <feature-slug or ADR-NNNN>
status: draft | proposed | accepted | superseded | deprecated | rejected
created: 2026-05-11           # KST date
updated: 2026-05-11
authors: [spec-shaman]        # persona slugs
related_tickets: [T-0042]     # optional
related_adrs: [ADR-0007]      # optional
---
```

## When to create what — driven by Technoking's complexity verdict

| Complexity | PRD | Design Doc | ADR | Notes |
|---|---|---|---|---|
| **small** | — | — | — | Direct to `/task`. No docs. |
| **medium** | merged | merged | optional | One combined `*-spec.md` (PRD + Design). ADR only if a trigger fires. |
| **large** | required | required | conditional | Separate files. ADR per qualifying decision. |

A `medium` complicating into `large` mid-flight (auto-escalation) → split the merged spec into separate PRD and Design at that point; do not retrofit history.

## ADR triggers — create one if **any** apply

When in doubt, create the ADR — cheap insurance.

1. **External dependency change** — adding/replacing a library, framework, payment provider, or external API.
2. **Storage or data-flow change** — DB engine swap, sync→async pipeline, cache introduction, event-bus introduction.
3. **Public/shared interface change** — contract used by 3+ callers, cross-module DTO change, public API surface.
4. **Auth, permission, or security-policy change** — anything affecting AuthN/AuthZ flow, secret handling, or compliance scope.

If an ADR is created, the corresponding Design Doc must list it under **Prerequisite ADRs**.

## Document specs

### PRD — `docs/prd/<feature-slug>-prd.md`

**Author**: Spec Shaman. **Approval**: Stop step in `large` only (medium has merged spec → one combined Stop).

**Required sections**:

1. **배경 / 문제** — what's broken or missing, who hurts, why now
2. **목표 / Non-goals** — outcome statements; non-goals explicitly listed
3. **사용자 가치 / 핵심 시나리오** — 1–3 user journeys
4. **Acceptance Criteria** — `AC-001`, `AC-002`, … each with a measurable pass condition. Sequential IDs are referenced from Design Doc and tickets.
5. **MoSCoW** — Must / Should / Could / Won't (Won't is required, not optional)
6. **성공 지표** — each KPI has a numeric target and measurement method
7. **스코프 경계 다이어그램** — Mermaid. What is in vs adjacent vs out
8. **오픈 질문** — anything blocking; flagged for discussion

**Out of scope for PRD**: implementation choices, tech stack, schedule. Those belong in Design / ADR / tickets.

### Design Doc — `docs/design/<feature-slug>-design.md`

**Author**: Galaxy Brain. **Approval**: Stop step in `medium` (combined with PRD) and `large` (standalone).

**Required sections**:

1. **요약 / 접근 방식** — vertical / horizontal / hybrid slice and why
2. **Prerequisite ADRs** — list with links
3. **기존 코드 분석** — files inspected (paths + functions), integration points
4. **인터페이스 / 계약** — function signatures, API shapes, message schemas. New + changed only.
5. **데이터 흐름 다이어그램** — Mermaid sequence or flow diagram
6. **변경 영향 맵** — direct impact / indirect impact / no ripple, by file or module
7. **AC 검증 전략** — for each `AC-NNN`, the verification method and threshold
8. **UI 명세** (frontend features only) — screen list, state matrix (default/loading/empty/error), key interactions, a11y. Co-authored by Pixel Wizard. Co-located here, not a separate UI Spec doc.
9. **위험 / 미해결** — known unknowns, fallbacks

**Out of scope for Design Doc**: business rationale (PRD), technology selection rationale (ADR), task breakdown (tickets).

### ADR — `docs/adr/ADR-NNNN-<kebab-title>.md`

**Author**: Galaxy Brain. **Approval**: bundled with the Design Doc Stop. **Numbering**: zero-padded 4-digit, monotonically increasing.

**Status lifecycle**: `proposed` → `accepted` → (`superseded by ADR-NNNN` | `deprecated`).

**Required sections**:

1. **컨텍스트** — what forced this decision
2. **결정** — one sentence. What was chosen.
3. **검토한 옵션** — minimum 3, including the chosen one. Each option: pros, cons, cost.
4. **근거** — why the chosen option won
5. **결과 / 영향** — what this enables, what it forecloses, what teams/files must change
6. **원칙적 가이드라인** — derived rules implementers should follow (e.g., "always use parameterized queries through this layer")

A new ADR that overrides an old one sets the old one's status to `superseded` and links forward.

### Diagnose — `docs/diagnose/<YYYY-MM-DD>-<topic-slug>.md`

**Author**: Galaxy Brain (or Technoking direct, for quick triage). **Approval**: none. Diagnose is investigative output, not a decision.

**Required sections**:

1. **증상 / 재현 절차** — what was observed, how to reproduce (commands, inputs)
2. **수집 증거** — logs, stack traces, query plans, file:line references inspected
3. **타임라인** — when it started, what changed around then (commit hashes, deploys)
4. **가설과 검증** — each hypothesis with the test that confirmed or ruled it out
5. **근본 원인** — single sentence. If unknown, say so and list remaining hypotheses.
6. **권장 조치** — fix path(s), each linked to a proposed ticket or PRD-worthy gap
7. **재발 방지** — guardrails (tests, lint, runtime check, alert)

A diagnose doc may spawn a `BL-NNNN` backlog item, a new ticket, or — for a proven systemic issue — a PRD.

## Diagram requirements (minimum)

| Doc | Required Mermaid |
|---|---|
| PRD | scope-boundary diagram |
| Design Doc | data-flow OR sequence diagram |
| ADR | option-comparison diagram **only when** options interact spatially (architecture moves, layering shifts) — a table is fine otherwise |
| Diagnose | timeline diagram **only when** ≥3 events interact across components |

Don't pad documents with pro-forma diagrams. A diagram that doesn't earn its space goes.

## Approval and Stop policy (cross-reference)

| Doc | small | medium | large |
|---|---|---|---|
| PRD | — | merged with Design (1 Stop) | standalone Stop |
| Design Doc | — | merged with PRD (1 Stop) | standalone Stop |
| ADR | — | bundled with Design Stop if any | bundled with Design Stop |
| Diagnose | none | none | none |

This matches `orchestration-guide`'s Stop policy (B-pattern, shinpr-style). When in doubt, refer to that skill.

## Reviewer expectations (Roastmaster's doc-quality bar)

A doc earns BLOCKING from Roastmaster if it:

- omits a required section listed above
- has ACs without measurable thresholds
- has an ADR with fewer than 3 options or no trade-offs
- mixes PRD and Design content in `large` (e.g., implementation steps in PRD, business rationale in Design)
- has stale frontmatter (`updated` not bumped after substantive edits)
- has commented-out or placeholder text shipped as "draft"

Pass-with-comments is acceptable for diagrams that could be clearer, prose that could be tighter, or open questions that have a reasonable owner. BLOCKING is reserved for missing structure or unverifiable claims.

## When this skill conflicts with the AC

If acceptance criteria explicitly waive a section (e.g., "no diagram needed for this trivial spec"), follow the AC and note the waiver in the doc's frontmatter under a `waivers:` list. Do not silently drop required structure.
