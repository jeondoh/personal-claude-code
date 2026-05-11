---
name: coding-principles
description: Stack-agnostic coding principles for the personal-claude-code workflows plugin. Use when implementing features, refactoring, or reviewing code — applies to all personas (Paladin, Wizard, Roastmaster) regardless of language. Stack-specific rules live in stack-* plugins; this skill stays language-neutral.
---

# Coding Principles (stack-agnostic)

These rules apply across every persona that touches code (Paladin, Wizard, and Roastmaster's review bar). Stack specifics (Kotlin idioms, React hooks, etc.) belong in `stack-*` plugins.

Testing rules → `testing-principles`. Doc rules → `documentation-criteria`. Commit/PR rules → `git-flow`.

## Core philosophy

1. **Maintainability over speed.** Prefer code a future reader (often you, in a different ticket) can understand without context.
2. **Simplest thing that satisfies AC.** YAGNI. No speculative abstraction, no future-proofing for hypothetical requirements.
3. **Explicit over implicit.** Names, types, and control flow should reveal intent — comments should not be the primary carrier.
4. **Delete > deprecate > comment-out.** If it's unused, remove it. Git remembers.

## Stay inside ticket scope

A ticket has acceptance criteria (AC) and a defined file set. Do not refactor adjacent code "while you're there."

- **IF** you spot a bug or smell in code outside your AC → file a `BL-NNNN` backlog ticket and keep moving. Do not silently fix it in this ticket.
- **IF** the AC cannot be satisfied without touching out-of-scope code → escalate via worker inbox (`escalation_needed: true`). Do not expand scope unilaterally.
- Rationale: scope creep blocks reviewers, breaks atomic commits, and conflicts with parallel workers in other panes.

Within scope, opportunistic cleanup is fine: fix a misnamed local var in a function you're already editing.

## Naming and readability

- Use full domain words. Abbreviate only when the abbreviation is more recognizable than the full word in this domain (`http`, `id`, `url`).
- Single-letter names are loop counters or math conventions only (`i`, `x`, `y`).
- Extract magic numbers and string literals into named constants when used more than once or when the name carries meaning.
- Code self-documents the *what*. Save comments for *why*.

## Function design

- 0–2 parameters preferred. 3+ → group into an object/struct/dataclass.
- One responsibility per function. Single level of abstraction inside the body.
- Hard ceiling: nesting depth 3. Use early returns or extract helpers to flatten.
- Soft ceiling: ~50 lines per function. Hard ceiling: 100. Past 100, the function almost certainly hides a missing abstraction.
- Prefer pure functions. Separate computation from I/O — push side effects to the edge.

## Error handling

- **Validate at boundaries only.** User input, external API responses, file/network reads. Trust internal callers — re-validating defensively just hides bugs.
- **Fail fast and loud.** No silent fallbacks, no swallowed exceptions, no `catch { return null }` without context. The worker's inbox needs a real error to escalate; a swallowed exception becomes a 2-hour debugging session.
- **Propagate with context.** When wrapping or rethrowing, attach the operation that failed (not just the underlying error message).
- **Never log secrets.** Mask tokens, passwords, full PII. Use field allowlists when logging request/response bodies.

## Dependencies and coupling

- Inject collaborators (constructor params, function args). Do not reach for global state or service locators.
- Depend on interfaces/abstractions when there is more than one realistic implementation or when the boundary will be mocked in tests. Otherwise concrete is fine — abstractions are not free.
- Module direction: domain core depends on nothing; adapters depend on the core. If a "core" file imports from `infra/` or `web/`, the layering is wrong.

## Verify before adopting nearby patterns

Nearby code is a starting point for investigation, not authority.

- **IF** you found a pattern in 2–3 files near your target → grep the repo before adopting it. Confirm it's the majority pattern.
- **IF** multiple approaches coexist → pick the dominant one and state your reason in the PR. "It's what the file next door does" is not a reason.
- **IF** the answer is genuinely unclear → escalate. Do not pick at random.

## Refactoring policy

- Refactor in **its own commit**, separate from behavior changes. A reviewer should not have to spot a logic change inside a 200-line move-rename.
- Refactor triggers (within scope): duplication that's been copy-pasted ≥ 3 times, function over the line ceiling, branching logic that needs a comment to read, name that misleads.
- Do not chase perfection. Leave the code one notch better than you found it.

## Comments

Default: write none. The bar to add a comment is "would a careful reader of this code be confused or surprised without it?"

- Comment **why**, not **what**. The code already says what.
- Acceptable: hidden invariant, workaround for a specific bug (link the issue), non-obvious performance trade-off, intentional deviation from a nearby pattern.
- Forbidden: restating the code, change-log style notes ("added for ticket T-0042", "removed deprecated branch"), TODO without an owner and date.
- Delete commented-out code immediately. Git is the archive.

## Security defaults

These are floor-level expectations; the security review goes deeper.

- Secrets via env var or secret manager. Never in source, never in logs.
- Parameterized queries / prepared statements for every DB call. String concatenation into SQL is an automatic BLOCKING from Roastmaster.
- Cryptographically secure RNG for tokens, IDs, nonces (`SecureRandom`, `crypto.randomBytes`, etc.). Never `Math.random()`/`Random()` for anything security-adjacent.
- Validate every external input for shape, type, length, and allowed values at the entry point. Encode every output for its rendering context (HTML escape, SQL bind, shell quote, URL encode).
- Authorize per resource access, not just at the route entry. AuthN ≠ AuthZ.
- Apply least privilege to file modes, DB roles, API scopes, and IAM grants.

## Quality bar (Roastmaster will block on)

Language-agnostic gating rules. Stack-specific BLOCKING items live in `stack-*` skills.

- Function exceeding the hard ceiling (100 lines).
- Nesting depth > 3 in production code.
- Swallowed exception (`catch { }` with no logging or rethrow).
- Plaintext secret in source or in logs.
- Non-parameterized SQL — string concatenation into a query.
- `Math.random()` / `Random()` for security-relevant values (tokens, nonces, IDs).
- Commented-out code shipped to main.
- Refactor mixed into the same commit as a behavior change.
- Out-of-scope changes silently bundled instead of filed as `BL-NNNN`.

## When this skill conflicts with the AC

If a principle here conflicts with surrounding code, follow this skill and note the deviation in your PR. If it conflicts with the ticket AC, follow the AC and flag the principle in the worker inbox so Technoking can decide.
