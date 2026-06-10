---
name: testing-nextjs
description: Test framework and patterns for Next.js + TypeScript — Vitest, React Testing Library, MSW, Playwright. Use whenever tests are written or reviewed in this stack. Stack-specific overlay on testing-principles.
---

# Testing — Next.js + TypeScript

Overlay on `testing-principles`. On divergence this skill wins for Next.js/Vitest/Playwright.

## Frameworks & Versions (pinned)

| Layer | Tool | Notes |
|---|---|---|
| Runner | **Vitest** (1.x/2.x) | native ESM/TS, Vite-aligned |
| Component | **React Testing Library** (`@testing-library/react`) | matches React 19 |
| User event | `@testing-library/user-event` | over `fireEvent` |
| HTTP mocking | **MSW** v2+ | `http.get` / `HttpResponse.json`; v1 syntax (`rest.get`, `ctx.json`) is BLOCKING |
| E2E | **Playwright** (latest) | `/feat` acceptance + cross-browser |
| DOM env | `jsdom` (default) or `happy-dom` | pinned per project |

Jest forbidden in new code; migrate existing Jest tests when touched.

## Canonical commands

Rescue trigger matches these strings:

- `pnpm test` — Vitest full suite
- `pnpm test -- <file-pattern>` — single file
- `pnpm test:e2e` — Playwright full suite
- `pnpm test:e2e -- --grep '<spec>'` — single spec

## Test types

| Type | Tool | Speed | Use for |
|---|---|---|---|
| Pure function | Vitest | < 100 ms | utilities, hooks logic, reducers |
| Component | Vitest + RTL | < 200 ms | render + interaction, props/state |
| Server Component (async) | Vitest + React `experimental` test util | < 500 ms | render with awaited fetch (MSW) |
| Route Handler / Server Action | Vitest | < 200 ms | direct invocation, no HTTP layer |
| E2E / Acceptance | Playwright | seconds | What-If Witch's `/feat` AC tests, full-stack flows |

Default: component tests with RTL + MSW. Playwright for `/feat` acceptance, full user flows, or real-browser needs.

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

Component tests co-located. E2E in top-level `e2e/`, out of the unit runner.

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

```ts
// tests/setup.ts
import "@testing-library/jest-dom/vitest";
import { afterAll, afterEach, beforeAll } from "vitest";
import { server } from "./msw/server";

beforeAll(() => server.listen({ onUnhandledRequest: "error" }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
```

`onUnhandledRequest: "error"` — any unmocked URL **fails** the test, so tests never hit the real network.

## React Testing Library patterns

### Query priority (RTL official, enforced)

```
1. getByRole / findByRole       (accessibility-anchored)
2. getByLabelText               (forms)
3. getByText                    (visible content)
4. getByDisplayValue            (form values)
5. getByTestId                  (last resort)
```

`getByTestId` sparingly — a component that needs test IDs to be queryable has an a11y problem; fix the component.

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

`fireEvent` forbidden in new tests; `userEvent` simulates real input (focus, keyboard, paste).

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

Disable retries in tests — they hide failures and slow the suite.

## MSW patterns

Default `setupServer` (Node) for Vitest. `setupWorker` (browser) only for Playwright with mocked APIs. Pin one stance per project in the Design Doc.

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

- One handler file per domain (`handlers/users.ts`, `handlers/auth.ts`) when the file grows.
- Per-test override: `server.use(http.get("/api/users", () => HttpResponse.error()))` for failure cases.
- Reuse handlers in Playwright via the `msw` browser integration when E2E mocks APIs.

## Server Component / Server Action testing

- Server Action: import and call directly with `FormData` (or fixture). Assert return value and any `revalidateTag` mock.
- Route Handler: invoke exported `GET` / `POST` directly with a `Request`.
- Async Server Component: React's experimental async test util is unstable. **Recommended**: extract data-fetching into a server-only function, unit-test it directly, and test the wrapping Client Component for rendered output. Avoid full async-render tests until React's utilities stabilize.

No full Next dev server in unit tests — that's E2E.

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

- `AC-NNN` in acceptance test names (matches PRD).
- Network: real test backend OR MSW-in-browser; pin one per environment.
- Fixed test data per run; reset between specs.
- One Playwright project per browser engine if cross-browser matters; default chromium-only for `/feat` acceptance.

## Coverage and CI

- Vitest V8 coverage, 80% lines/functions on changed files.
- Playwright runs on PR (block-on-failure, excluded from the 10-min unit budget).
- Failed tests upload screenshots / traces as CI artifacts.

## Common smells (Roastmaster blocks on)

- `getByTestId` everywhere instead of role/label queries.
- `fireEvent` in new code.
- Real network call (no MSW handler — caught by `onUnhandledRequest: "error"`).
- `await waitFor(() => ...)` polling an arbitrary time instead of asserting a specific reachable state.
- `Math.random` / `new Date()` without fixed seed / fixed clock.
- Snapshot test of a large component (use targeted assertions).
- E2E asserting on internal CSS class names (use roles and text).
- Skipped (`it.skip`, `test.skip`, `xit`) without a linked ticket.

## When this skill conflicts with the AC

E2E flakiness from third-party widgets may justify a `getByTestId` exception or longer `expect` timeout. Document the deviation in the test file with a comment + linked ticket; otherwise follow this skill.
