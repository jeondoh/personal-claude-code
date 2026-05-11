# stack-nextjs

Next.js + TypeScript 프로젝트용 스킬 묶음. `workflows` 코어 위에 얹어, 워커가 App Router · Server Components · Server Actions 같은 Next.js 고유 패턴을 자동으로 알게 한다.

## 들어있는 것

| 스킬 | 다루는 영역 |
|---|---|
| [`nextjs-core`](skills/nextjs-core/SKILL.md) | App Router, Server/Client Component boundary, 캐싱, a11y, TypeScript 컨벤션 |
| [`frontend-data`](skills/frontend-data/SKILL.md) | Server Component fetch, Server Actions, TanStack Query, zod 검증, 5-state UI |
| [`testing-nextjs`](skills/testing-nextjs/SKILL.md) | Vitest · React Testing Library · MSW v2 · Playwright |

추가로 `hooks/stop-verification.sh` — 워커의 turn 이 끝날 때 `pnpm test` 를 자동 실행해 빨간 테스트로 PR 이 나가는 걸 막는다.

## 설치

```bash
/plugin marketplace add sideholic/personal-claude-code
/plugin install workflows@personal-claude-code     # 코어 (필수)
/plugin install stack-nextjs@personal-claude-code  # 이 스택
```

## 버전 정책

스킬 안의 권장값 (예: "Next.js 15 의 Server Actions") 은 작성 시점 스냅샷이지, 강제 핀이 아니다. 워커는 실제 적용 시점에 프로젝트의 `package.json` 을 읽어 설치된 버전을 확인하고, 학습 데이터에 없는 새 버전이면 공식 문서를 검색해 검증한다 (detect-and-verify).

## 정본

`package.json` — 설치된 Next.js / React / TypeScript / TanStack Query 버전의 진실의 원천. 스킬과 충돌하면 `package.json` 이 이긴다.

## 관련 문서

- [상위 README](../../README.md) — 전체 7 인 팀과 라이프사이클 소개
- [`workflows/skills/coding-principles`](../../workflows/skills/coding-principles/SKILL.md) — 이 스택이 얹히는 stack-agnostic 코딩 원칙
- [`workflows/skills/testing-principles`](../../workflows/skills/testing-principles/SKILL.md) — stack-agnostic 테스트 원칙

## 라이선스

MIT — [`LICENSE`](../../LICENSE).
