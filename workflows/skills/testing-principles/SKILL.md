---
name: testing-principles
description: Stack-agnostic testing principles for the personal-claude-code workflows plugin. Use whenever a persona writes, reviews, or plans tests — applies to What-If Witch (acceptance + integration + E2E), Paladin/Wizard (unit), and Roastmaster's test-quality bar. Stack-specific test framework guidance lives in stack-* plugins (testing-kotlin, testing-nextjs).
---

# Testing Principles (stack-agnostic)

Tests are first-class code. Roastmaster reviews test code at the same bar as production code. Stack specifics (Kotest vs Vitest, MockK vs Jest mocks) live in `stack-*/skills/testing-*`.

## Core philosophy

1. **Tests gate merges, not coverage numbers.** Coverage is a guide, not a goal.
2. **Test observable behavior, not implementation.** Refactor should not require test rewrites.
3. **Independent, deterministic, fast.** Order-independent. Same input → same result. Unit < 100 ms / integration < 1 s / full suite < 10 min.
4. **A test without an assertion is dead weight.** A test whose expected value equals the mock return verifies nothing.

## Test pyramid (per ticket)

| Type | Owner | When | Speed budget |
|---|---|---|---|
| Unit | Paladin / Wizard | Same commit as production code | < 100 ms |
| Integration (real I/O) | Paladin / Wizard | When code crosses a boundary (DB, HTTP, FS) | < 1 s |
| Acceptance | What-If Witch | Step 7 of `/feat` lifecycle, **fail-first commit** before implementation | < 5 s |
| E2E | What-If Witch | Step 10 (large only by default; medium if AC requires) | seconds |

What-If Witch writes acceptance tests **before** Paladin/Wizard start (red commit). This is the AC contract.

## Acceptance test contract (What-If Witch)

- Each `AC-NNN` from PRD/Design maps to ≥ 1 acceptance test.
- Test **must fail at first commit** (proves AC is real and verifiable).
- Test name follows `AC-NNN: should <behavior> when <condition>` so the trace is mechanical.
- An AC that cannot be expressed as a test → escalate, do not invent one. Untestable AC is an auto-escalation trigger.

## TDD where it pays — not as dogma

- **Apply RED-GREEN-REFACTOR** for: AC tests (always), pure logic with branching, bug fixes (write the regression test first).
- **Skip TDD** for: scaffolding, configuration, boilerplate adapters, throwaway spikes (delete the spike, write tests for the kept code).
- A test added after the fact must still fail without the fix — verify by reverting the fix and re-running.

## Structure — AAA only

```
Arrange → Act → Assert
```

No branching, no loops, no shared mutable fixtures across tests. If you find yourself looping inside a test, you wanted parameterized/table-driven tests — use the framework's mechanism.

Test name: `should <expected> when <condition>` (or stack equivalent — describe/it for JS, `@DisplayName` for Kotlin).

## Mocking — the boundary rule

Mock at **external I/O boundaries**: HTTP clients, DB drivers, message brokers, filesystem, clock, RNG. Use real implementations for internal collaborators.

Boundary is the rule, not "everything that's slow." Mocking your own service in a service-level test verifies wiring, not behavior.

**Hard rule for data access**: repository implementations are **not unit tested with mocks**. Mocks pass schema mismatches, query bugs, and constraint violations through silently. Repository tests run against a real DB engine (Testcontainers / in-memory engine that matches dialect / dedicated test DB). See stack `data-access` and `testing-*` skills for stack-specific setup.

**AI-generated query hazard**: AI-written SQL/JPQL/ORM code has elevated schema-hallucination risk. Roastmaster pattern-matches on this and will BLOCK if a data-access change has only mock-based tests.

## Fixtures and helpers

- Each test creates its own data. No shared state mutated between tests.
- Test data builders (factories) for any entity used in 3+ tests.
- Cleanup: every resource the test acquires is released in teardown — even on failure.
- Fixed clock and fixed seed for any time-dependent or random-dependent test.

## What you must always test

For any non-trivial function, cover:

1. **Happy path** — normal expected input.
2. **Boundaries** — min, max, just-below, just-above, empty.
3. **Error cases** — invalid input, missing data, downstream failure.
4. **Side effects** — verify DB write, message published, log emitted (when these are part of the contract).

For any bug fix:

5. **Regression test** — fails without the fix.

## What not to test

- Private methods directly. Test through the public surface.
- Framework code (Spring's DI wiring, Next.js routing internals).
- Trivial getters/setters with no logic.
- Order of internal calls (implementation detail, not behavior).

## Quality bar (Roastmaster will block on)

- Test with no assertion → BLOCKING.
- `expected = mockReturn` (assertion verifies nothing) → BLOCKING.
- Repository / data-access change with no real-DB integration test → BLOCKING.
- Acceptance test missing for any `AC-NNN` in scope → BLOCKING.
- Skipped (`@Disabled`, `it.skip`, `xit`, `@Ignore`) test merged without a linked ticket explaining why → BLOCKING.
- Flaky test (non-deterministic clock, unbounded race, real network) → BLOCKING.
- Commented-out test code shipped → BLOCKING (delete or fix).

Pass-with-comments is fine for: missing edge case that's not covered by the ticket AC, name nits, fixture extraction opportunities.

## Test scope vs ticket scope

- Tests live in the **same commit** as the production change.
- Adding tests for unrelated existing code = scope creep → file `BL-NNNN`.
- Failing pre-existing test discovered mid-ticket: do not silently fix. Decide:
  - **IF** the failure is caused by your change → fix in this ticket.
  - **IF** pre-existing → file `BL-NNNN`, mention in PR, leave the test failing-but-flagged or `@Disabled` with link to the BL ticket.

## Verification before PR

- All tests pass locally (or in pane's headless run).
- No `.skip`/`@Disabled`/`@Ignore` without a linked ticket.
- New tests fail without the production change (verify by stashing the change).
- No real network, no real clock, no real RNG without explicit opt-in.

## When this skill conflicts with the AC

If an AC explicitly waives a test type (e.g., "no E2E required for this internal-only change"), follow the AC, record the waiver in the Design Doc's `waivers:` field, and surface the waiver in the PR description so Roastmaster can approve the gap.
