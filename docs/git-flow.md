# Git 흐름 — 사용자 가이드

이 마켓이 git 을 어떻게 다루는지 사용자 관점에서 정리. 워커가 자동으로 만드는 브랜치·커밋·PR 의 패턴을 알고 있으면 관찰·개입이 쉬워진다.

상세 정책은 `workflows/skills/git-flow/SKILL.md` (페르소나용) 참조.

## 브랜치 명명

| 패턴 | 용도 |
|---|---|
| `feat/T-NNNN-<slug>` | 일반 작업 ticket — Paladin / Wizard 가 생성 |
| `task/T-NNNN-<slug>` | small `/task` 라우팅 |
| `rescue/T-NNNN` | codex rescue 패치 결과를 받아 검증할 때 |
| `hotfix/<slug>` | 사용자가 수동으로 만드는 긴급 수정 |

브랜치는 항상 `main` 에서 분기한다. 워커는 자기 worktree 안에서만 작업하므로 `main` 작업 트리는 사용자가 자유롭게 사용 가능.

## worktree

각 워커는 `.worktrees/<branch-slug>/` 에 격리된 worktree 를 가진다. `git worktree list` 로 모두 확인 가능. ticket 머지 후 Technoking 가 자동으로 `git worktree remove` 한다.

`.worktrees/` 는 gitignore. `/cleanup` 명령으로 orphan worktree (in-progress 가 아닌 ticket 의 worktree) 식별·제거.

## 커밋 메시지

[Conventional Commits](https://www.conventionalcommits.org/) 형식. 예:

```
feat(billing): add idempotency key to charge endpoint
fix(auth): reject expired refresh tokens
refactor(api): extract pagination helper
test(billing): add fail-first AC for retry path
```

**ticket 참조 강제**: 본문 끝에 `Refs: T-0042` 라인. 머지 후 ticket 추적 용이.

**Co-author 라인**: AI 도구를 거친 커밋이라는 출처 표기는 워커가 자동 처리.

## PR 사이즈 가이드

| 등급 | 라인 |
|---|---|
| 권장 | ≤ 400 (added + removed) |
| 한도 | ≤ 800 |
| 초과 | 분할 강제 — Roastmaster BLOCKING |

큰 변경은 step 6 task decomposition 단계에서 ticket 분할로 회피. PR 한 개 = ticket 한 개 = 워커 한 명 = ≤ 400줄 가까이.

## PR 템플릿

워커가 PR 을 열 때 자동 채움 (커맨드는 `gh pr create`):

```
## Summary
<티켓 핵심 변경 1–3 줄>

## Related ticket
T-NNNN

## Test plan
- [ ] AC 1 통과
- [ ] AC 2 통과
- [ ] CI green

## Review checklist
- [ ] codex /codex:adversarial-review 비차단 dispatch 완료
- [ ] Roastmaster verdict 판정 (codex 결과 도착 후)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

## 머지 전략

`main` 에 **squash 머지**. 한 PR = 한 commit. ticket id (`Refs: T-NNNN`) 가 squash commit body 에 남아 추적 가능.

force-push to `main` / `master` 는 `block-dangerous.sh` 훅이 차단. 우회하려면 명시적 환경에서 훅을 끄거나 직접 git 명령 사용 (마켓의 룰 위배).

## hotfix 흐름 (사용자 수동)

긴급 상황에서 라이프사이클 우회:

1. `git checkout -b hotfix/<slug> main`
2. 직접 수정 + 커밋
3. PR 생성 후 `/review #<PR>` 으로 Roastmaster 리뷰 강제 (선택, 그러나 권장).
4. Roastmaster `APPROVE` 후 squash 머지.
5. 후속 ticket (`/feat` 또는 `/task`) 으로 정식 흐름 처리. hotfix 는 임시.

hotfix 는 `T-NNNN` 카운터 소비 X — registry.json 건드리지 않음.

## CI 게이트

Stop 훅 (`stop-verification.sh`) 이 워커의 turn 마다 빌드·테스트를 자동 실행. 실패 시 워커가 "done" 신호 못 보냄. PR 단계의 CI 도 동일 게이트 — green 아니면 Roastmaster 가 자동 BLOCKING.

테스트 일시 비활성화: `CLAUDE_TEAM_SKIP_VERIFY=1` 환경변수 (개발 중 빠른 반복용, PR 머지 전 반드시 해제).

## 더 알아보기

- 페르소나용 git 정책 (브랜치 생성·rebase·conflict 처리): `workflows/skills/git-flow/SKILL.md`
- ticket 흐름과 git 의 매핑: `docs/ticket-protocol.md`
- 리뷰 + codex: `workflows/skills/adversarial-review-bridge/SKILL.md`
