# testing-nextjs

Next.js + TypeScript 테스트 코드의 프레임워크 선택과 패턴 (Vitest·React Testing Library·MSW·Playwright).

## 무엇을 하나

이 스킬은 stack-agnostic `testing-principles` 위에 얹히는 Next.js 테스트 오버레이다.
러너는 Vitest (Jest 금지), 컴포넌트 테스트는 React Testing Library + `userEvent` (`fireEvent` 금지),
HTTP mocking 은 MSW v2 (`http.get` / `HttpResponse.json` 문법), E2E 는 Playwright 로 핀한다.

쿼리 우선순위 (`getByRole` 최상, `getByTestId` 최후), `onUnhandledRequest: "error"` 로 실제 네트워크 차단,
`AC-NNN` 네이밍 traceability 같은 룰을 모은다.
Pixel Wizard (unit/component) 와 What-If Witch (E2E·acceptance) 양쪽이 본다.

## 언제 작동하나

이 스택에서 테스트를 작성하거나 리뷰할 때 활성화된다.
`testing-principles` 의 일반 룰 (피라미드·실제-의존성 선호·flake 금지) 을 먼저 적용하고 그 위에 Next.js 전용 framework 컨벤션을 얹는다.

## 다루는 주제

- 프레임워크 핀 (Vitest / RTL / `userEvent` / MSW v2 / Playwright / jsdom 디폴트)
- 테스트 타입별 속도 목표 (pure 100ms / component 200ms / Server Action 200ms / Server Component 500ms / E2E 수 초)
- File structure (component test 는 co-located, E2E 는 top-level `e2e/`, shared MSW handlers 는 `tests/msw/`)
- Vitest setup·MSW `setupServer` + `onUnhandledRequest: "error"` 강제 (실제 네트워크 호출 시 테스트 fail)
- RTL 쿼리 우선순위 (`getByRole` → `getByLabelText` → `getByText` → `getByDisplayValue` → `getByTestId`) 와 `userEvent` 인터랙션
- 커스텀 render (`QueryClientProvider` wrap, `retry: false` 강제)
- Server Component / Server Action / Route Handler 테스트 전략 (직접 호출 패턴, 풀 Next dev 서버 회피)
- Playwright `AC-NNN` 네이밍·MSW-in-browser 옵션·screenshot/trace 아티팩트
- Coverage 게이트 (V8 80% on changed files) 와 Roastmaster 가 블록하는 smell

## 정본 (Source of Truth)

설치된 Vitest / Testing Library / MSW / Playwright 버전은 `package.json` 이 정본이다.
MSW v1 → v2 는 시그니처 BLOCKING break (`rest.get` → `http.get`, `ctx.json` → `HttpResponse.json`),
TanStack Query v5 는 retry / `enabled` 동작이 바뀌어 테스트에서 명시 옵션이 필요하다.

training cutoff 보다 새로운 메이저에서는 공식 docs 를 확인한 뒤 쓰고, async Server Component test util 은 아직 unstable 이므로 데이터 fetch 함수를 분리해 단위 테스트하는 패턴을 권장한다.

## 같이 보는 스킬

- [`SKILL.md`](SKILL.md) — Claude 가 실제로 읽는 본문
- [`../../../workflows/skills/testing-principles/SKILL.md`](../../../workflows/skills/testing-principles/SKILL.md) — 상위 stack-agnostic 테스트 원칙
- [`../nextjs-core/SKILL.md`](../nextjs-core/SKILL.md) — production 측 컨벤션 (테스트는 Server/Client boundary 를 따라간다)
- [`../frontend-data/SKILL.md`](../frontend-data/SKILL.md) — Server Action·TanStack Query 패턴 (MSW 로 검증)
