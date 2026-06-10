---
name: coding-principles
description: Stack-agnostic coding principles for the personal-claude-code workflows plugin. Use when implementing features, refactoring, or reviewing code — applies to all personas (Paladin, Wizard, Roastmaster) regardless of language. Stack-specific rules live in stack-* plugins; this skill stays language-neutral.
---

# Coding Principles (stack-agnostic)

Applies to every persona that touches code (Paladin, Wizard, Roastmaster's review bar). Stack specifics (Kotlin idioms, React hooks) → `stack-*` plugins. Testing → `testing-principles`. Docs → `documentation-criteria`. Commit/PR → `git-flow`.

## Core philosophy

1. **Maintainability over speed.** Readable without context (often by future-you in another ticket).
2. **Simplest thing that satisfies AC.** YAGNI — no speculative abstraction, no hypothetical future-proofing.
3. **Explicit over implicit.** Names, types, control flow reveal intent; comments aren't the primary carrier.
4. **Delete > deprecate > comment-out.** Unused → remove. Git remembers.

## Stay inside ticket scope

A ticket has acceptance criteria (AC) and a defined file set. Do not refactor adjacent code "while you're there." Scope creep blocks reviewers, breaks atomic commits, conflicts with parallel workers.

- Bug/smell outside your AC → file a `BL-NNNN` backlog ticket and keep moving. Do not silently fix it here.
- AC unsatisfiable without out-of-scope code → escalate via worker inbox (`escalation_needed: true`). Do not expand scope unilaterally.
- Within scope, opportunistic cleanup is fine (e.g. fix a misnamed local var in a function you're already editing).

## Naming and readability

- Full domain words. Abbreviate only when the abbreviation beats the full word in this domain (`http`, `id`, `url`).
- Single-letter names = loop counters / math conventions only (`i`, `x`, `y`).
- Extract magic numbers / string literals into named constants when used >1 time or when the name carries meaning.
- Code self-documents the *what*; comments are for *why*.

## Function design

- 0–2 params preferred. 3+ → group into an object/struct/dataclass.
- One responsibility, single level of abstraction per body.
- Nesting depth: **hard ceiling 3**. Flatten via early returns or extracted helpers.
- Length: soft ~50 lines, **hard ceiling 100**. Past 100 = a missing abstraction.
- Prefer pure functions. Separate computation from I/O; push side effects to the edge.

## Error handling

- **Validate at boundaries only** — user input, external API responses, file/network reads. Trust internal callers; defensive re-validation hides bugs.
- **Fail fast and loud.** No silent fallbacks, swallowed exceptions, or `catch { return null }` without context — the inbox needs a real error to escalate.
- **Propagate with context.** When wrapping/rethrowing, attach the failed operation (not just the underlying message).
- **Never log secrets.** Mask tokens, passwords, full PII. Use field allowlists when logging request/response bodies.

## Dependencies and coupling

- Inject collaborators (constructor params, function args). No global state or service locators.
- Depend on interfaces/abstractions only when >1 realistic implementation exists or the boundary is mocked in tests. Otherwise concrete — abstractions aren't free.
- Module direction: domain core depends on nothing; adapters depend on the core. A "core" file importing from `infra/` or `web/` = wrong layering.

## Verify before adopting nearby patterns

Nearby code is a starting point, not authority.

- Pattern found in 2–3 nearby files → grep the repo first; confirm it's the majority pattern.
- Multiple approaches coexist → pick the dominant one and state your reason in the PR. "It's what the file next door does" is not a reason.
- Genuinely unclear → escalate. Do not pick at random.

## Refactoring policy

- Refactor in **its own commit**, separate from behavior changes. No logic change buried in a 200-line move-rename.
- Triggers (within scope): copy-paste duplication ≥3 times, function over the line ceiling, branching that needs a comment to read, misleading name.
- Don't chase perfection — leave code one notch better than you found it.

## Comments

Default: none. Bar to add one: "would a careful reader be confused or surprised without it?" Comment **why**, not **what**.

- Acceptable: hidden invariant, bug workaround (link the issue), non-obvious perf trade-off, intentional deviation from a nearby pattern.
- Forbidden: restating the code; change-log notes ("added for ticket T-0042", "removed deprecated branch"); TODO without owner and date.
- Delete commented-out code immediately. Git is the archive.

## Security defaults

Floor-level; the security review goes deeper.

- Secrets via env var or secret manager. Never in source, never in logs.
- Parameterized queries / prepared statements for every DB call. SQL string concatenation = automatic BLOCKING from Roastmaster.
- Cryptographically secure RNG for tokens, IDs, nonces (`SecureRandom`, `crypto.randomBytes`). Never `Math.random()`/`Random()` for anything security-adjacent.
- Validate every external input (shape, type, length, allowed values) at the entry point. Encode every output for its rendering context (HTML escape, SQL bind, shell quote, URL encode).
- Authorize per resource access, not just at the route entry. AuthN ≠ AuthZ.
- Least privilege on file modes, DB roles, API scopes, IAM grants.

## Quality bar (Roastmaster will block on)

Language-agnostic gating. Stack-specific BLOCKING items → `stack-*` skills.

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

Conflict with surrounding code → follow this skill, note the deviation in your PR. Conflict with the ticket AC → follow the AC, flag the principle in the worker inbox so Technoking can decide.
