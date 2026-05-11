---
name: nextjs-core
description: Next.js (App Router) and TypeScript conventions for frontend code in this team. Use when Pixel Wizard (or any persona) writes or reviews Next.js code. Layered on top of the stack-agnostic coding-principles skill — read that first, then apply these stack-specific rules.
---

# Next.js (App Router) — Core

Stack-specific overlay on `coding-principles`. Pinned to App Router (no Pages Router for new code). When this skill and `coding-principles` agree, follow `coding-principles`. When they diverge, this skill wins for Next.js/TypeScript code.

## Versions and tooling (pinned)

| Item | Choice |
|---|---|
| Next.js | 15.x (App Router) |
| React | 19.x |
| Node | ≥ 20.11 LTS |
| TypeScript | 5.x |
| Package manager | pnpm 9.x |
| Language | TypeScript only — no `.js`/`.jsx` in `app/`, `components/`, `lib/` |
| `tsconfig` | `strict: true`, `noUncheckedIndexedAccess: true`, `noFallthroughCasesInSwitch: true` |
| Lint / format | ESLint (`next/core-web-vitals`) + Prettier; pre-commit fails on either |

## Canonical commands

Rescue trigger matches on these strings (the `error_signature` calculation in `adversarial-review-bridge` depends on these commands' error output format):

- `pnpm build` — Next build + type check
- `pnpm lint`
- `pnpm typecheck`
- `pnpm test` — Vitest
- `pnpm test:e2e` — Playwright

## Project structure

```
app/                              # App Router routes
├── (marketing)/                  # route group, not a URL segment
├── (app)/                        # authenticated app routes
│   ├── layout.tsx
│   └── <feature>/
│       ├── page.tsx              # Server Component by default
│       ├── loading.tsx
│       ├── error.tsx
│       └── _components/          # private to this route (underscore prefix)
├── api/                          # Route Handlers (only when client cannot reach backend directly)
└── layout.tsx                    # root layout — server-only

components/                       # cross-feature reusable UI
├── ui/                           # primitives (Button, Input)
└── <feature>/                    # feature-specific shared components

lib/                              # framework-free helpers
├── api/                          # API client wrappers
├── auth/
└── utils/

types/                            # shared TS types (rarely; prefer co-location)
```

Route-private components go in `_components/` (Next ignores underscore-prefixed dirs for routing). Cross-route reuse → `components/`.

## Server vs Client Components

### Default: Server Component

- Every component is a Server Component unless it explicitly opts out with `"use client"`.
- Server Components: data fetching, secrets access, large dependency rendering.
- Client Components: interactivity (event handlers, state, effects), browser-only APIs.

### `"use client"` placement

- Push the boundary as **deep** as possible. A whole page declared `"use client"` defeats the architecture.
- Pattern: server `page.tsx` → server component composes static content + a small client island for interactive parts.

### Forbidden in Server Components

`useState`, `useEffect`, `useReducer`, browser globals (`window`, `localStorage`), event handlers (`onClick`, `onChange`). If you need any of these, extract a client component for that part only.

## Data fetching (high level)

Detailed patterns in `frontend-data` skill. Summary here:

- Server Components: `fetch` directly, with Next's caching primitives (`{ cache, next: { revalidate, tags } }`).
- Client Components: TanStack Query (default; SWR if pinned project-wide). No raw `useEffect` for data fetching.
- Mutations: Server Actions (`"use server"`) for typed RPC; Route Handlers when an external HTTP API is needed.

**authN ≠ authZ**: every Server Action that mutates protected resources must check **per-resource authorization**, not only authentication. authN-only Server Action on protected data is BLOCKING.

**useTransition**: wrap Server Action invocations from interactive Client Components in `useTransition` to prevent UI freeze; surface in-flight state via `isPending`.

## Routing patterns

- Dynamic segments: `[slug]`, `[...slug]`, `[[...slug]]` (optional catch-all). Prefer named over catch-all.
- Parallel routes (`@modal`): for slot-based composition (modals, side panels).
- Intercepting routes (`(.)`, `(..)`, `(...)`): for in-place modal patterns. Use sparingly — they confuse new contributors.
- Route Groups `(name)`: organize without affecting URL.

## Styling

- Tailwind CSS, configured per project.
- CSS Modules acceptable for genuinely-isolated component styles.
- No global CSS beyond `globals.css` (resets, fonts, theme variables).
- No styled-components / Emotion — these conflict with Server Components.

## Components — quality bars

### Naming

- PascalCase component names. File names match the default export (`UserCard.tsx` exports `UserCard`).
- Hooks: `useThing` — file `useThing.ts`.
- Utility modules: kebab-case files, named exports (`format-date.ts` exports `formatDate`).

### Props

- Explicit props interface on every component:
  ```tsx
  type Props = { user: User; onEdit?: (id: string) => void };
  export function UserCard({ user, onEdit }: Props) { … }
  ```
- No `React.FC<Props>` — it brings legacy `children` typing baggage.
- Boolean props default false. Don't add a prop just because.

### Accessibility (a11y)

- Every interactive element is reachable by keyboard.
- Every form input has a label (visible or `aria-label`).
- Every image has `alt` (empty string if decorative).
- Focus management on route changes and modal open/close.
- Color contrast ≥ AA against the background.

Pixel Wizard owns a11y; Roastmaster BLOCKS on missing `alt`, unreachable controls, or missing labels.

## Performance

- Image: `next/image`. No raw `<img>` for product imagery.
- Font: `next/font`. No `<link>` to Google Fonts.
- Code splitting: dynamic `import()` for heavy components only loaded after interaction.
- Avoid waterfalls: kick off independent fetches in parallel via `Promise.all` in Server Components.
- Streaming: wrap independent async Server Components in `<Suspense fallback={...}>`. Default-await behavior blocks the whole page until every fetch resolves.

## Caching invariants

- `fetch` defaults are version-dependent — be **explicit**:
  ```ts
  fetch(url, { cache: "no-store" });                 // every request
  fetch(url, { next: { revalidate: 60 } });          // 60s ISR
  fetch(url, { next: { tags: ["user", id] } });      // tag-based invalidation
  ```
- Revalidate on mutations via `revalidateTag` / `revalidatePath` from the Server Action.
- Document the caching strategy of every `fetch` in the Design Doc.

## Environment variables

- Server-only secrets: `MY_SECRET=...` — never accessed in client components.
- Public: `NEXT_PUBLIC_THING=...` — bundled into client.
- Validate at startup with `zod` (or equivalent). A missing or malformed env var should fail boot, not surface as a runtime error.

## TypeScript rules

- `strict: true`. Period.
- No `any`. Use `unknown` and narrow.
- No `// @ts-ignore` — use `// @ts-expect-error <reason>` when the suppression is intentional and short-lived.
- Discriminated unions for state machines (`{ status: "loading" } | { status: "ready"; data: ... } | { status: "error"; error: Error }`).
- Inferred return types for functions are fine, but **export interfaces** for public APIs (libraries, shared modules).

## Common smells (Roastmaster blocks on)

- `"use client"` at the top of a route segment that doesn't need it.
- `useEffect` for data fetching in a client component (use TanStack Query / Server Components).
- Server-only secret accessed in a `"use client"` file.
- Missing `alt` on image, missing label on input.
- Raw `<img>` tag in product UI.
- `any` introduced as escape hatch.
- Cross-feature import going through `../../../`. Use absolute imports or restructure.
- Router state (`useRouter`, `usePathname`) used in a Server Component.

## When this skill conflicts with the AC

If an AC requires a deviation (legacy Pages Router maintenance, third-party widget that requires global CSS), document in Design Doc and Pixel Wizard signs off. Otherwise follow this skill.
