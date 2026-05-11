# stack-kotlin-spring

Kotlin + Spring Boot 프로젝트용 스킬 묶음. `workflows` 코어 위에 얹어, 워커가 Kotlin/Spring 고유의 함정과 컨벤션을 자동으로 알게 한다.

## 들어있는 것

| 스킬 | 다루는 영역 |
|---|---|
| [`kotlin-spring-boot-core`](skills/kotlin-spring-boot-core/SKILL.md) | Clean Architecture 4-layer, Kotlin 이디엄, Spring 설정, 트랜잭션 경계 |
| [`data-access`](skills/data-access/SKILL.md) | JPA · `JdbcClient` · Flyway, repository 패턴, N+1 회피 |
| [`testing-kotlin`](skills/testing-kotlin/SKILL.md) | JUnit 5 · Kotest · MockK · Testcontainers, real-DB 테스트 |

추가로 `hooks/stop-verification.sh` — 워커의 turn 이 끝날 때 `./gradlew test` 를 자동 실행해 빨간 테스트로 PR 이 나가는 걸 막는다.

## 설치

```bash
/plugin marketplace add sideholic/personal-claude-code
/plugin install workflows@personal-claude-code            # 코어 (필수)
/plugin install stack-kotlin-spring@personal-claude-code  # 이 스택
```

## 버전 정책

스킬 안의 권장값 (예: "Spring Boot 4 의 `JdbcClient`") 은 작성 시점 스냅샷이지, 강제 핀이 아니다. 워커는 실제 적용 시점에 프로젝트의 `build.gradle.kts` 를 읽어 설치된 버전을 확인하고, 학습 데이터에 없는 새 버전이면 공식 문서를 검색해 검증한다 (detect-and-verify).

## 정본

`build.gradle.kts` — 설치된 Kotlin / Spring Boot / Hibernate / Flyway 버전의 진실의 원천. 스킬과 충돌하면 `build.gradle.kts` 가 이긴다.

## 관련 문서

- [상위 README](../../README.md) — 전체 7 인 팀과 라이프사이클 소개
- [`workflows/skills/coding-principles`](../../workflows/skills/coding-principles/SKILL.md) — 이 스택이 얹히는 stack-agnostic 코딩 원칙
- [`workflows/skills/testing-principles`](../../workflows/skills/testing-principles/SKILL.md) — stack-agnostic 테스트 원칙

## 라이선스

MIT — [`LICENSE`](../../LICENSE).
