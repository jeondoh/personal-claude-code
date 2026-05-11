# nextjs-core

Next.js (App Router) + TypeScript 프론트엔드 코드에 적용되는 stack-specific 컨벤션 (Server/Client boundary·routing·a11y·캐싱).

## 무엇을 하나

이 스킬은 stack-agnostic `coding-principles` 위에 얹히는 Next.js/TypeScript 오버레이다. App Router 만 사용 (Pages Router 금지), Server Component 가 디폴트이고 `"use client"` 는 가능한 한 깊게 내려쓰는 boundary 룰, `strict: true` TypeScript, Tailwind + `next/image` + `next/font`, a11y 바 (alt·label·키보드 도달) 같은 BLOCKING 패턴을 한 곳에 모은다. 주 사용자는 Pixel Wizard (Frontend) 이고, Roastmaster 가 PR 리뷰 시 이 스킬의 룰을 게이트로 쓴다.

## 언제 작동하나

Pixel Wizard (또는 다른 페르소나) 가 Next.js 코드를 작성하거나 리뷰할 때 활성화된다. `coding-principles` 를 먼저 읽고 그 위에 stack 룰을 적용하는 순서다.

## 다루는 주제

- Version detect-and-verify protocol (`package.json` 기준, 새 메이저는 docs 확인)
- Canonical pnpm 명령어 (rescue trigger 가 이 문자열 매칭)
- Project structure (`app/`·`_components/` privacy·`components/`·`lib/`)
- Server vs Client Component boundary 와 `"use client"` 배치 룰
- Routing 패턴 (dynamic segment·parallel route·route group)
- Tailwind 스타일링·a11y 바 (Roastmaster BLOCKING)
- Performance (`next/image`·`next/font`·`<Suspense>` streaming·parallel fetch)
- 캐싱 invariants 와 environment variable 분리·TypeScript strict 룰

## 정본 (Source of Truth)

설치된 Next.js / React / TypeScript / pnpm 버전은 `package.json` 이 정본이다. 스킬에 적힌 "Next 15+ / React 19+" 는 작성 시점 스냅샷일 뿐 핀이 아니다. `fetch` cache 디폴트·`next.config` 스키마·Server Action 시그니처·route segment config 는 메이저마다 변하므로 training cutoff 보다 새로운 버전에서는 WebFetch 로 공식 docs 확인 후 PR 본문에 verification line 을 남긴다.

## 같이 보는 스킬

- [`SKILL.md`](SKILL.md) — Claude 가 실제로 읽는 본문
- [`../../../workflows/skills/coding-principles/SKILL.md`](../../../workflows/skills/coding-principles/SKILL.md) — 상위 stack-agnostic 코딩 원칙
- [`../frontend-data/SKILL.md`](../frontend-data/SKILL.md) — Server Action·TanStack Query·캐싱 세부 패턴
- [`../testing-nextjs/SKILL.md`](../testing-nextjs/SKILL.md) — Vitest·RTL·MSW·Playwright 테스트 규약
