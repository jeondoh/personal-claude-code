---
name: frontend-data
description: Data fetching, caching, and mutation patterns for Next.js — Server Components fetch, Server Actions, TanStack Query, error/loading states. Use whenever Pixel Wizard implements or reviews data flow in the frontend. Stack-specific overlay; companion to nextjs-core.
---

# Frontend Data — Next.js

Patterns and bars for fetching, caching, and mutating data in this stack. Read `nextjs-core` first. When this skill and `coding-principles` (or `nextjs-core`) agree, follow them; when they diverge, this skill wins for data-fetching/mutation code.

## Versions (pinned)

| Item | Choice |
|---|---|
| TanStack Query | v5+ — v4 syntax (`useQuery(['key'], fn)`) is BLOCKING; use object form `useQuery({ queryKey, queryFn })` |
| Zod | 3.x |

## Decision tree

```
Where is the data needed?

├─ Server Component (page.tsx, layout.tsx, server-rendered children)
│    → fetch() directly, with explicit caching
│
└─ Client Component (interactivity required)
     │
     ├─ Read (list, detail, paginated)
     │    → TanStack Query (useQuery)
     │
     └─ Mutation (create / update / delete)
          ├─ Triggered by user action in a Client Component
          │    → Server Action (preferred), or TanStack Query useMutation
          │
          └─ Triggered by external system (webhook, etc.)
               → Route Handler (app/api/<thing>/route.ts)
```

Default: Server Components for initial render, TanStack Query for client-side reactive data, Server Actions for mutations.

## Server Component fetching

```tsx
// app/(app)/users/page.tsx
async function UsersPage() {
  const users = await fetch(`${API}/users`, {
    next: { revalidate: 60, tags: ["users"] },
  }).then(r => r.json());

  return <UserList users={users} />;
}
```

Rules:

- **Always specify caching**. `fetch` defaults change by Next version — make intent explicit.
- **Parallelize** independent fetches: `const [a, b] = await Promise.all([fetchA(), fetchB()]);`.
- **Validate response shape** with `zod` at trust boundaries — AI-written code hallucinates response shapes; schema validation catches drift.
- **No client component imports** inside the fetch path. Pure server logic.

## Caching and revalidation

| Need | Mechanism |
|---|---|
| Static for build-time only | `cache: "force-cache"` |
| Periodic refresh (ISR) | `next: { revalidate: <seconds> }` |
| Tag-based, refreshed on mutation | `next: { tags: ["..."] }` + `revalidateTag` from Server Action |
| Always fresh | `cache: "no-store"` |
| Authenticated user data | `cache: "no-store"` (cookies bust shared cache anyway, but be explicit) |

Document the caching strategy in the Design Doc — every `fetch` cached with a non-default policy needs a one-line rationale.

## Server Actions (mutations)

```tsx
// app/(app)/users/actions.ts
"use server";

import { revalidateTag } from "next/cache";
import { z } from "zod";

const Input = z.object({ name: z.string().min(1), email: z.string().email() });

export async function createUser(formData: FormData) {
  const parsed = Input.safeParse({
    name: formData.get("name"),
    email: formData.get("email"),
  });
  if (!parsed.success) {
    return { ok: false, error: parsed.error.flatten() };
  }

  const res = await fetch(`${API}/users`, {
    method: "POST",
    body: JSON.stringify(parsed.data),
    headers: { "Content-Type": "application/json" },
  });
  if (!res.ok) return { ok: false, error: { message: "create_failed" } };

  revalidateTag("users");
  return { ok: true };
}
```

Rules:

- **Validate every input at the top**. Server Actions are public endpoints — treat them like API routes.
- **Return a discriminated union** for ok/error states. The client handles both.
- **Revalidate explicitly** — `revalidateTag` or `revalidatePath` after a successful write.
- **Authenticate and authorize** before mutating. authN ≠ authZ — every Server Action mutating a protected resource must verify **per-resource authorization**, not just "is the user logged in". authN-only on protected data is BLOCKING.
- **Wrap invocations in `useTransition`** when called from interactive Client Components — keeps the UI responsive and exposes `isPending` for non-blocking pending indicators (`useFormStatus` for form submissions).

## TanStack Query patterns

### Query keys

```ts
// lib/api/queries.ts
export const userKeys = {
  all: ["users"] as const,
  list: (filter: Filter) => [...userKeys.all, "list", filter] as const,
  detail: (id: string) => [...userKeys.all, "detail", id] as const,
};
```

Centralized key factory. No ad-hoc string keys scattered across components.

### Query

```tsx
"use client";
import { useQuery } from "@tanstack/react-query";

function UserList({ filter }: Props) {
  const { data, error, isLoading } = useQuery({
    queryKey: userKeys.list(filter),
    queryFn: () => fetchUsers(filter),
    staleTime: 60_000,
  });

  if (isLoading) return <Spinner />;
  if (error) return <ErrorState error={error} />;
  if (!data) return null;
  return <Users users={data} />;
}
```

### Mutation + cache update

```tsx
const queryClient = useQueryClient();
const mutation = useMutation({
  mutationFn: createUser,
  onSuccess: () => queryClient.invalidateQueries({ queryKey: userKeys.all }),
});
```

Prefer `invalidateQueries` over manual `setQueryData` unless the mutation response is a complete replacement for the cached value.

### Forbidden

- `useEffect(() => fetch(...))` — use `useQuery`.
- Polling without `staleTime` and `refetchInterval` set deliberately. Aimless polling burns battery.
- Conditional hooks (calling `useQuery` inside an `if`). Use the `enabled` option.

### SSR hydration

SSR + TanStack Query: prefetch on the server, dehydrate to a serializable state, hydrate in the Client subtree. Avoids loading flash on first paint and double-fetch on mount.

```tsx
// Server Component
const queryClient = new QueryClient();
await queryClient.prefetchQuery({ queryKey: userKeys.list(filter), queryFn: () => fetchUsers(filter) });
return <HydrationBoundary state={dehydrate(queryClient)}><UserList filter={filter} /></HydrationBoundary>;
```

## Loading, empty, error states — the matrix

For every component that fetches or accepts async data, render explicitly:

| State | Render |
|---|---|
| `loading` | `<Spinner />` or skeleton |
| `empty` (loaded, no items) | `<EmptyState message=... action=... />` |
| `error` | `<ErrorState error=... onRetry=... />` |
| `partial` (some data, some failed) | partial render + non-blocking error indicator |
| `ready` | the data |

UI Spec section in Design Doc must include this matrix per component (see `documentation-criteria` Design Doc spec).

## Authentication / authorization

- Cookies as auth transport (HTTP-only, Secure, SameSite=Lax).
- Server Components / Actions read auth via `cookies()` from `next/headers`.
- Client Components receive auth state via context populated at the root layout.
- Authorization checks happen **server-side**. Client-side gates are UX hints, not security boundaries.

## Error boundaries

- Route-level `error.tsx` for uncaught render errors. Logs to telemetry, shows recovery UI.
- Component-level error boundaries via `react-error-boundary` for islands that should not bring down the page.
- Global handler (`app/global-error.tsx`) for the worst case.

## Forms

- Server Actions are the default for form submission.
- Client-side validation with `zod` (mirrors the server schema).
- Display server validation errors in the same component that renders the form.
- `useFormStatus` for in-flight pending state. `useOptimistic` for optimistic UI when latency matters.

## Common smells (Roastmaster blocks on)

- `useEffect` data fetching in a client component.
- `fetch` without explicit cache option.
- Server Action without input validation.
- Server Action without auth check on protected data.
- Inline `queryKey: ["users", filter]` instead of using the key factory.
- Loading / empty / error state missing — UI just renders nothing on non-ready states.
- Schema-less response handling (assuming the API returned what we expect without parsing).

## When this skill conflicts with the AC

A high-traffic dashboard with custom caching requirements may justify deviations. Document in Design Doc with measured numbers; otherwise follow this skill.
