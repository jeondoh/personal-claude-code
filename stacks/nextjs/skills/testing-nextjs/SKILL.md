---
name: testing-nextjs
description: Test framework and patterns for Next.js + TypeScript — Vitest, React Testing Library, MSW, Playwright. Use whenever tests are written or reviewed in this stack. Stack-specific overlay on testing-principles.
---

# Testing — Next.js + TypeScript

Stack-specific overlay on `testing-principles`. When this skill and `testing-principles` agree, follow `testing-principles`. When they diverge, this skill wins for Next.js/Vitest/Playwright tests.

## Frameworks (pinned choices)

| Layer | Tool | Why |
|---|---|---|
| Test runner | **Vitest** | fast, native ESM/TS, Vite-aligned with Next's bundling story |
| Component testing | **React Testing Library** (`@testing-library/react`) | behavior-focused, semantic queries |
| User event | `@testing-library/user-event` | realistic interaction over `fireEvent` |
| HTTP mocking | **MSW** (Mock Service Worker) | intercepts at the request layer; same handlers in unit + E2E |
| E2E | **Playwright** | for `/feat` acceptance + cross-browser runs |
| DOM environment | `jsdom` (fast) or `happy-dom` (faster, slight gaps) | pinned per project; default `jsdom` |

Jest is forbidden in new code; existing Jest tests are migrated when touched.

## Versions (pinned)

| Item | Choice |
|---|---|
| Vitest | 1.x or 2.x |
| Testing Library / React | matches React 19 |
| MSW | v2+ — v1 syntax (`rest.get(...)`, `ctx.json(...)`) is BLOCKING; use `http.get` / `HttpResponse.json` |
| Playwright | latest |

## Canonical commands

Rescue trigger matches on these strings:

- `pnpm test` — Vitest full suite
- `pnpm test -- <file-pattern>` — single file
- `pnpm test:e2e` — Playwright full suite
- `pnpm test:e2e -- --grep '<spec>'` — single spec

## Test types

| Type | Tool | Speed | Use for |
|---|---|---|---|
| Pure function | Vitest | < 100 ms | utilities, hooks logic, reducers |
| Component | Vitest + RTL | < 200 ms | render + interaction, props/state |
| Server Component (async) | Vitest with React `experimental` test util | < 500 ms | render with awaited fetch (MSW) |
| Route Handler / Server Action | Vitest | < 200 ms | direct invocation, no HTTP layer |
| E2E / Acceptance | Playwright | seconds | What-If Witch's `/feat` AC tests, full-stack flows |

Default: component tests with RTL + MSW. Reach for Playwright for `/feat` acceptance tests, full user flows, or anything that genuinely needs a real browser.

## File structure

```
src/
├── app/
├── components/
│   └── UserCard/
│       ├── UserCard.tsx
│       └── UserCard.test.tsx        # co-located
├── lib/
│   └── format-date.test.ts
└── tests/
    ├── msw/
    │   └── handlers.ts              # shared MSW handlers
    └── support/
        └── render.tsx               # custom render with providers

e2e/                                  # Playwright
├── fixtures/
└── <feature>.spec.ts
```

Component tests are **co-located**. E2E lives in a top-level `e2e/` dir, kept out of the unit runner.

## Vitest setup essentials

```ts
// vitest.config.ts (excerpt)
export default defineConfig({
  test: {
    environment: "jsdom",
    setupFiles: ["./tests/setup.ts"],
    globals: true,
    coverage: { provider: "v8", thresholds: { lines: 80, functions: 80 } },
  },
});
```

`tests/setup.ts`:

```ts
import "@testing-library/jest-dom/vitest";
import { afterAll, afterEach, beforeAll } from "vitest";
import { server } from "./msw/server";

beforeAll(() => server.listen({ onUnhandledRequest: "error" }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
```

`onUnhandledRequest: "error"` — any test that hits a URL without an MSW handler **fails**, guaranteeing tests don't accidentally reach the real network.

## React Testing Library patterns

### Query priority (RTL official, enforced)

```
1. getByRole / findByRole       (accessibility-anchored)
2. getByLabelText               (forms)
3. getByText                    (visible content)
4. getByDisplayValue            (form values)
5. getByTestId                  (last resort)
```

`getByTestId` should appear sparingly. If a component is consistently hard to query without test IDs, the component has an a11y problem — fix the component, not the test.

### Interaction

```tsx
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";

test("should submit form with entered email", async () => {
  const user = userEvent.setup();
  render(<SignupForm onSubmit={onSubmit} />);

  await user.type(screen.getByLabelText(/email/i), "alice@example.com");
  await user.click(screen.getByRole("button", { name: /sign up/i }));

  expect(onSubmit).toHaveBeenCalledWith({ email: "alice@example.com" });
});
```

`fireEvent` is forbidden in new tests. `userEvent` simulates real input (focus, keyboard, paste).

### Custom render

```tsx
// tests/support/render.tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render } from "@testing-library/react";

export function renderWithProviders(ui: React.ReactElement) {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  return render(<QueryClientProvider client={queryClient}>{ui}</QueryClientProvider>);
}
```

Disable retries in tests — retries hide real failures and slow the suite.

## MSW patterns

Default: `setupServer` (Node) for Vitest unit/component tests. `setupWorker` (browser) only for Playwright when E2E uses mocked APIs. Pin one stance per project in the Design Doc.

```ts
// tests/msw/handlers.ts
import { http, HttpResponse } from "msw";

export const handlers = [
  http.get("/api/users", () => HttpResponse.json([{ id: "1", name: "Alice" }])),
  http.post("/api/users", async ({ request }) => {
    const body = await request.json();
    return HttpResponse.json({ id: "new", ...body }, { status: 201 });
  }),
];
```

- One handler file per logical domain (`handlers/users.ts`, `handlers/auth.ts`) when the file gets long.
- Per-test override: `server.use(http.get("/api/users", () => HttpResponse.error()))` to inject failure cases.
- Handlers reused by Playwright via the `msw` browser integration when E2E uses mocked APIs.

## Server Component / Server Action testing

- Server Action: import and call directly with a `FormData` (or fixture). Assert the return value and any `revalidateTag` mock.
- Route Handler: invoke the exported `GET` / `POST` directly with a `Request` instance.
- Async Server Component: React's experimental async test utility is still unstable. **Recommended pattern**: extract data-fetching into a server-only function, unit-test that function directly, and test the wrapping Client Component (or a thin Server Component composing already-tested pieces) for rendered output. Avoid full async-render tests until React's test utilities stabilize.

Avoid spinning up a full Next dev server in unit tests — that's E2E territory.

## Playwright (E2E and `/feat` acceptance)

```ts
// e2e/signup.spec.ts
import { test, expect } from "@playwright/test";

test("AC-001: should sign up new user with valid email", async ({ page }) => {
  await page.goto("/signup");
  await page.getByLabel(/email/i).fill("alice@example.com");
  await page.getByRole("button", { name: /sign up/i }).click();
  await expect(page.getByText(/welcome, alice/i)).toBeVisible();
});
```

Rules:

- `AC-NNN` in the test name for acceptance tests (matches PRD).
- Network: either real test backend OR MSW-in-browser. Pin one per environment.
- Fixed test data per run. Reset between specs.
- One Playwright project per browser engine if cross-browser matters; default to chromium-only for `/feat` acceptance.

## Coverage and CI

- Vitest's V8 coverage. Threshold 80% lines/functions on changed files.
- Playwright runs on PR but is allowed to be slower (block-on-failure, but excluded from the 10-min budget that unit tests respect).
- Failed tests upload screenshots / traces as CI artifacts.

## Common smells (Roastmaster blocks on)

- `getByTestId` everywhere instead of role/label queries.
- `fireEvent` in new code.
- Test makes a real network call (no MSW handler — caught by `onUnhandledRequest: "error"`).
- `await waitFor(() => ...)` polling for an arbitrary time instead of asserting a specific reachable state.
- `Math.random` / `new Date()` inside a test without fixed seed / fixed clock.
- Snapshot test of a large component (snapshots that nobody reads are noise; use targeted assertions).
- E2E test asserting on internal CSS class names (use roles and text).
- Skipped (`it.skip`, `test.skip`, `xit`) without a linked ticket.

## When this skill conflicts with the AC

E2E flakiness from third-party widgets may justify a `getByTestId` exception or a longer `expect` timeout. Document the deviation in the test file with a comment + linked ticket; otherwise follow this skill.
