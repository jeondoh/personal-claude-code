# frontend-data

Next.js 프론트엔드의 데이터 fetching·캐싱·mutation 패턴 (Server Component fetch·Server Action·TanStack Query).

## 무엇을 하나

이 스킬은 `nextjs-core` 위에 얹히는 데이터 흐름 전용 오버레이다. "어디서 데이터가 필요한가" 로 시작하는 decision tree (Server Component 면 `fetch`, Client read 면 TanStack Query, Client mutation 이면 Server Action), `fetch` cache 옵션 명시 의무, Server Action 에서 zod 입력 검증과 per-resource 인가 (authN ≠ authZ BLOCKING), `useTransition` 으로 UI 반응성 유지, loading/empty/error/partial/ready 5-state matrix 같은 룰을 한 곳에 모은다. 주 사용자는 Pixel Wizard.

## 언제 작동하나

Pixel Wizard 가 프론트엔드 데이터 흐름을 구현하거나 리뷰할 때 활성화된다. `nextjs-core` 를 먼저 읽고 그 위에 데이터 fetching·mutation 룰을 얹는다.

## 다루는 주제

- Data location decision tree (Server Component / Client / Mutation / Webhook)
- Server Component `fetch` 룰 (cache 명시·`Promise.all` 병렬화·zod 응답 검증)
- 캐싱·revalidation 매트릭스 (`force-cache`·ISR·tag-based·`no-store`)
- Server Action (입력 검증·discriminated union·`revalidateTag`·인가·`useTransition`)
- TanStack Query v5 key factory·query·mutation·SSR hydration 패턴
- Loading / empty / error / partial / ready 5-state UI matrix
- 인증·인가 (cookie 기반, server-side 게이트가 정본) 와 error boundary
- 폼 (Server Action 디폴트, `useFormStatus`·`useOptimistic`)

## 정본 (Source of Truth)

설치된 Next.js / TanStack Query / zod 버전은 `package.json` 이 정본이다. TanStack Query v4 → v5 의 시그니처 변화 (`useQuery({ queryKey, queryFn })` object form 강제) 같은 메이저 break 는 BLOCKING 이므로 새 메이저에서는 공식 docs 를 확인한 뒤 쓴다. `fetch` cache 디폴트는 Next 메이저마다 바뀌므로 항상 옵션을 명시한다.

## 같이 보는 스킬

- [`SKILL.md`](SKILL.md) — Claude 가 실제로 읽는 본문
- [`../nextjs-core/SKILL.md`](../nextjs-core/SKILL.md) — App Router·Server/Client boundary (이 스킬의 전제)
- [`../testing-nextjs/SKILL.md`](../testing-nextjs/SKILL.md) — MSW 로 Server Action / TanStack Query 검증
- [`../../../workflows/skills/coding-principles/SKILL.md`](../../../workflows/skills/coding-principles/SKILL.md) — 상위 stack-agnostic 코딩 원칙
