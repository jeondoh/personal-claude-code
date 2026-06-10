---
name: testing-principles
description: Stack-agnostic testing principles for the personal-claude-code workflows plugin. Use whenever a persona writes, reviews, or plans tests — applies to What-If Witch (acceptance + integration + E2E), Paladin/Wizard (unit), and Roastmaster's test-quality bar. Stack-specific test framework guidance lives in stack-* plugins (testing-kotlin, testing-nextjs).
---

# Testing Principles (stack-agnostic)

Tests are first-class code — Roastmaster reviews them at the production bar. Stack specifics (Kotest vs Vitest, MockK vs Jest mocks) live in `stack-*/skills/testing-*`.

## Core philosophy

1. **Tests gate merges, not coverage numbers.** Coverage guides; isn't a goal.
2. **Test observable behavior, not implementation.** Refactor shouldn't require test rewrites.
3. **Independent, deterministic, fast.** Order-independent; same input → same result. Unit < 100 ms / integration < 1 s / full suite < 10 min.
4. **No assertion → dead weight.** `expected = mockReturn` verifies nothing.

## Test pyramid (per ticket)

| Type | Owner | When | Speed |
|---|---|---|---|
| Unit | Paladin / Wizard | Same commit as production code | < 100 ms |
| Integration (real I/O) | Paladin / Wizard | Code crosses a boundary (DB, HTTP, FS) | < 1 s |
| Acceptance | What-If Witch | Step 7 of `/feat`, **fail-first commit** before implementation | < 5 s |
| E2E | What-If Witch | Step 10 (large only by default; medium if AC requires) | seconds |

What-If Witch writes acceptance tests **before** Paladin/Wizard start (red commit) — the AC contract.

## Acceptance test contract (What-If Witch)

- Each `AC-NNN` from PRD/Design → ≥ 1 acceptance test.
- Test **must fail at first commit** (proves the AC is real and verifiable).
- Name: `AC-NNN: should <behavior> when <condition>` (mechanical trace).
- AC that can't be a test → escalate, don't invent one. Untestable AC is an auto-escalation trigger.

## TDD where it pays — not as dogma

- **RED-GREEN-REFACTOR** for: AC tests (always), pure logic with branching, bug fixes (regression test first).
- **Skip TDD** for: scaffolding, config, boilerplate adapters, throwaway spikes (delete spike, test the kept code).
- A test added after the fact must still fail without the fix — verify by reverting the fix.

## Structure — AAA only

```
Arrange → Act → Assert
```

No branching, no loops, no shared mutable fixtures across tests. Looping inside a test = you wanted parameterized/table-driven — use the framework's mechanism.

Test name: `should <expected> when <condition>` (or stack equivalent — describe/it for JS, `@DisplayName` for Kotlin).

## Mocking — the boundary rule

Mock at **external I/O boundaries**: HTTP clients, DB drivers, message brokers, filesystem, clock, RNG. Real implementations for internal collaborators. Mocking your own service in a service-level test verifies wiring, not behavior.

**Hard rule for data access**: repository implementations are **not unit tested with mocks** — mocks pass schema mismatches, query bugs, and constraint violations through silently. Repository tests run against a real DB engine (Testcontainers / dialect-matching in-memory engine / dedicated test DB). See stack `data-access` and `testing-*` skills.

**Scope**: applies only to NEW or MODIFIED repository methods within ticket scope. A ticket merely calling an existing unchanged repository method needs no new Testcontainers test for it.

**AI-generated query hazard**: AI-written SQL/JPQL/ORM has elevated schema-hallucination risk. Roastmaster will BLOCK if a NEW or MODIFIED data-access method has only mock-based tests.

## Fixtures and helpers

- Each test creates its own data — no shared state mutated between tests.
- Test data builders (factories) for any entity used in 3+ tests.
- Every acquired resource released in teardown — even on failure.
- Fixed clock and fixed seed for any time- or random-dependent test.

## What you must always test

**Scope rule first**: only test NEW or MODIFIED code within the ticket's `files_in_scope`. Testing untouched code = scope creep (file a `BL-NNNN` if you spot a gap). Categories below apply within that scope.

For any NEW or MODIFIED non-trivial function:

1. **Happy path** — normal expected input.
2. **Boundaries** — min, max, just-below, just-above, empty.
3. **Error cases** — invalid input, missing data, downstream failure.
4. **Side effects** — DB write, message published, log emitted (when part of the contract).

For any bug fix:

5. **Regression test** — fails without the fix.

## What not to test

- Private methods directly (test through the public surface).
- Framework code (Spring DI wiring, Next.js routing internals).
- Trivial getters/setters with no logic.
- Order of internal calls (implementation detail).

## Quality bar (Roastmaster blocks on)

- Test with no assertion → BLOCKING.
- `expected = mockReturn` (verifies nothing) → BLOCKING.
- Repository / data-access change with no real-DB integration test → BLOCKING.
- Acceptance test missing for any `AC-NNN` in scope → BLOCKING.
- Skipped (`@Disabled`, `it.skip`, `xit`, `@Ignore`) test merged without a linked ticket explaining why → BLOCKING.
- Flaky test (non-deterministic clock, unbounded race, real network) → BLOCKING.
- Commented-out test code shipped → BLOCKING (delete or fix).

Pass-with-comments is fine for: missing edge case not covered by ticket AC, name nits, fixture extraction opportunities.

## Test scope vs ticket scope

- Tests live in the **same commit** as the production change.
- Tests for unrelated existing code = scope creep → file `BL-NNNN`.
- Failing pre-existing test discovered mid-ticket — don't silently fix:
  - **IF** caused by your change → fix in this ticket.
  - **IF** pre-existing → file `BL-NNNN`, mention in PR, leave failing-but-flagged or `@Disabled` with link to the BL ticket.

## Verification before PR

- All tests pass locally (or in pane's headless run).
- No `.skip`/`@Disabled`/`@Ignore` without a linked ticket.
- New tests fail without the production change (verify by stashing the change).
- No real network, clock, or RNG without explicit opt-in.

## When this skill conflicts with the AC

If an AC explicitly waives a test type (e.g., "no E2E for this internal-only change"), follow the AC, record the waiver in the Design Doc's `waivers:` field, and surface it in the PR description so Roastmaster can approve the gap.
