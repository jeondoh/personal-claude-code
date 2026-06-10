---
name: nextjs-core
description: Next.js (App Router) and TypeScript conventions for frontend code in this team. Use when Pixel Wizard (or any persona) writes or reviews Next.js code. Layered on top of the stack-agnostic coding-principles skill — read that first, then apply these stack-specific rules.
---

# Next.js (App Router) — Core

Stack-specific overlay on `coding-principles`. App Router only (no Pages Router for new code). On agreement, follow `coding-principles`; on divergence, this skill wins for Next.js/TypeScript code.

## Version handling — detect, don't assume

Applies to **whichever version is actually installed**, not a fixed pin. Reference table is a 2026-05 authoring snapshot; the project is the source of truth. Detect first, then verify against official docs when the installed version is outside training-data confidence.

### Reference (snapshot, not a mandate)

| Item | Reference | Detect from |
|---|---|---|
| Next.js | 15+ (App Router) | `package.json` → `dependencies.next` |
| React | 19+ | `package.json` → `dependencies.react` |
| Node | ≥ 20.11 LTS | `node --version`, `.nvmrc`, `package.json` → `engines.node` |
| TypeScript | 5+ | `package.json` → `devDependencies.typescript` |
| Package manager | pnpm 9+ | `package.json` → `packageManager` |

**Project conventions (version-independent — always apply):**

- TypeScript only — no `.js`/`.jsx` in `app/`, `components/`, `lib/`
- `tsconfig`: `strict: true`, `noUncheckedIndexedAccess: true`, `noFallthroughCasesInSwitch: true`
- Lint/format: ESLint (`next/core-web-vitals`) + Prettier; pre-commit fails on either
- App Router only (no Pages Router for new code)

### Protocol (BLOCKING when violated)

1. **Detect** installed Next.js/React major.minor from `package.json` at start of work. Record in design notes or PR description.
2. **Compare to training cutoff**. Evergreen concepts here (App Router architecture, Server vs Client boundary, `_components/` privacy, a11y bar, `useTransition` for Server Actions, fetch caching primitives) apply broadly.
3. **If installed version is newer than your confident training** OR you use a specific feature/config key/default/import path you're not 100% sure is stable in that version: **MUST verify via official docs before writing code**.
   - Next.js: https://nextjs.org/docs (WebFetch the specific page)
   - React: https://react.dev
   - TanStack Query / Vitest / MSW: their official sites
4. **Always re-verify (version-volatile)**: `fetch` cache defaults, `next.config.{js,ts}` schema, Server Action signature, `<Image>` / `next/font` props, route segment config (`export const dynamic`, `revalidate`, `runtime`).
5. **Never invent** feature names, config keys, defaults from training. When uncertain: WebFetch → read → code. If WebFetch fails or docs are ambiguous, escalate via `inbox/` rather than guess.
6. **Record verification** in PR description, e.g. `Verified against Next.js 16.2 § Data Fetching (2026-05-11)`. Roastmaster & codex use this to scope review.

## Canonical commands

Rescue trigger matches on these strings (the `error_signature` calculation in `adversarial-review-bridge` depends on their error output format):

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

Route-private components → `_components/` (Next ignores underscore-prefixed dirs for routing). Cross-route reuse → `components/`.

### Sub-folder guidance inside a feature directory

`components/ui/` (shadcn primitives) — **keep flat as an explicit exception**: shadcn CLI generates directly under this path and can't target sub-folders. Up to ~30 primitives stays readable. If shadcn gains sub-folder generation (or you drop its CLI), fall back to the semantic-role split below.

`components/<feature>/` (feature-specific shared) — **flat up to ~4 files, then split by semantic role** (what they *do*, not what they *are*):

```
components/shell/
├── layout/              # composition shells, skip links, page wrappers
├── nav/                 # sidebars, nav lists, mobile sheets
└── header/ (or topbar/) # top bars, breadcrumbs, theme toggles, user menus
```

Common axes: `layout/`, `nav/`, `header/`, `form/`, `data/`, `feedback/`. Don't over-engineer — a 3-file feature stays flat. Trigger is "I can't find anything in here anymore," not a strict count. May nest one more level for sub-features (`shell/nav/sidebar-section/`), but stop at three levels — deeper hides files.

## Server vs Client Components

**Default: Server Component.** Every component is a Server Component unless it opts out with `"use client"`.

- Server: data fetching, secrets access, large-dependency rendering.
- Client: interactivity (event handlers, state, effects), browser-only APIs.

**`"use client"` placement** — push the boundary as **deep** as possible. A whole-page `"use client"` defeats the architecture. Pattern: server `page.tsx` composes static content + a small client island for interactive parts.

**Forbidden in Server Components**: `useState`, `useEffect`, `useReducer`, browser globals (`window`, `localStorage`), event handlers (`onClick`, `onChange`). Need any → extract a client component for that part only.

## Data fetching (high level)

Detailed patterns in `frontend-data` skill. Summary:

- Server Components: `fetch` directly with Next's caching primitives (`{ cache, next: { revalidate, tags } }`).
- Client Components: TanStack Query (default; SWR if pinned project-wide). No raw `useEffect` for data fetching.
- Mutations: Server Actions (`"use server"`) for typed RPC; Route Handlers when an external HTTP API is needed.

**authN ≠ authZ**: every Server Action mutating protected resources must check **per-resource authorization**, not only authentication. authN-only Server Action on protected data is BLOCKING.

**useTransition**: wrap Server Action invocations from interactive Client Components in `useTransition` to prevent UI freeze; surface in-flight state via `isPending`.

## Routing patterns

- Dynamic segments: `[slug]`, `[...slug]`, `[[...slug]]` (optional catch-all). Prefer named over catch-all.
- Parallel routes (`@modal`): slot-based composition (modals, side panels).
- Intercepting routes (`(.)`, `(..)`, `(...)`): in-place modal patterns. Use sparingly — confuse new contributors.
- Route Groups `(name)`: organize without affecting URL.

## Styling

- Tailwind CSS, configured per project.
- CSS Modules acceptable for genuinely-isolated component styles.
- No global CSS beyond `globals.css` (resets, fonts, theme variables).
- No styled-components / Emotion — conflict with Server Components.

## Components — quality bars

**Naming**
- PascalCase component names. File matches default export (`UserCard.tsx` exports `UserCard`).
- Hooks: `useThing` — file `useThing.ts`.
- Utility modules: kebab-case files, named exports (`format-date.ts` exports `formatDate`).

**Props**
- Explicit props interface on every component:
  ```tsx
  type Props = { user: User; onEdit?: (id: string) => void };
  export function UserCard({ user, onEdit }: Props) { … }
  ```
- No `React.FC<Props>` — brings legacy `children` typing baggage.
- Boolean props default false. Don't add a prop just because.

**Accessibility (a11y)**
- Every interactive element reachable by keyboard.
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
- Streaming: wrap independent async Server Components in `<Suspense fallback={...}>`. Default-await blocks the whole page until every fetch resolves.

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
- Validate at startup with `zod` (or equivalent). Missing/malformed env var should fail boot, not surface as a runtime error.

## TypeScript rules

- `strict: true`. Period.
- No `any`. Use `unknown` and narrow.
- No `// @ts-ignore` — use `// @ts-expect-error <reason>` when suppression is intentional and short-lived.
- Discriminated unions for state machines (`{ status: "loading" } | { status: "ready"; data: ... } | { status: "error"; error: Error }`).
- Inferred return types are fine, but **export interfaces** for public APIs (libraries, shared modules).

## Common smells (Roastmaster blocks on)

- `"use client"` at the top of a route segment that doesn't need it.
- `useEffect` for data fetching in a client component (use TanStack Query / Server Components).
- Server-only secret accessed in a `"use client"` file.
- Missing `alt` on image, missing label on input.
- Raw `<img>` tag in product UI.
- `any` introduced as escape hatch.
- Cross-feature import through `../../../`. Use absolute imports or restructure.
- Router state (`useRouter`, `usePathname`) used in a Server Component.

## When this skill conflicts with the AC

If an AC requires a deviation (legacy Pages Router maintenance, third-party widget requiring global CSS), document in Design Doc and Pixel Wizard signs off. Otherwise follow this skill.
