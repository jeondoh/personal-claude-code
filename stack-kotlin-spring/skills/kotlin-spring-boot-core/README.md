# kotlin-spring-boot-core

Kotlin + Spring Boot 백엔드 코드에 적용되는 stack-specific 컨벤션 (Clean Architecture·Kotlin 이디엄·Spring 설정 규약).

## 무엇을 하나

이 스킬은 stack-agnostic `coding-principles` 위에 얹히는 Kotlin/Spring 전용 오버레이다.
4-layer Clean Architecture (api → application → domain ← infrastructure), 생성자 주입,
JPA 엔티티 작성 규칙 (`data class` 금지, `allOpen` 자동 주입), 코루틴 트랜잭션 경계,
`@RestControllerAdvice` 에러 envelope 같은 BLOCKING 패턴을 한 곳에 모은다.

주 사용자는 Persistence Paladin (Backend) 이고, Roastmaster 가 PR 리뷰 시 이 스킬의 룰을 게이트로 쓴다.
두 스킬이 충돌하면 이 파일이 Kotlin/Spring 코드에 한해 우선한다.

## 언제 작동하나

Persistence Paladin (또는 다른 페르소나) 이 Kotlin + Spring Boot 코드를 작성하거나 리뷰할 때 활성화된다.
`coding-principles` 를 먼저 읽고 그 위에 stack 룰을 적용하는 순서다.

## 다루는 주제

- Version detect-and-verify protocol (`build.gradle.kts` 기준, training cutoff 초과 시 official docs 확인)
- Kotlin compiler args 와 JPA + `allOpen` 동작 (no-arg constructor·`open` 자동 주입)
- Nullability·data class·`val`/`var`·extension function·`@JvmInline value class` 룰
- 코루틴 트랜잭션 경계 (`@Transactional` 과 `withContext(Dispatchers.IO)` 의 thread-local tx 문제)
- Clean Architecture 4-layer + DIP — repository interface 는 `application` 에 두고 JPA 구현은 `infrastructure`
- DI·configuration·web layer·logging·transaction 컨벤션
- Project structure 와 bounded context 배치 (one context per package)
- Canonical Gradle 명령어 (rescue trigger 가 이 문자열 매칭)
- Performance smells Roastmaster 가 블록하는 패턴 (N+1·blocking JDBC in coroutine·`runBlocking` in prod)

## 정본 (Source of Truth)

설치된 버전은 `build.gradle.kts` 가 정본이다.
스킬에 적힌 "JDK 24 / Kotlin 2.2 / Spring Boot 4" 는 작성 시점 스냅샷일 뿐 핀이 아니다.

training cutoff 보다 새로운 메이저가 깔려 있거나 starter 좌표·`spring.*` property key·auto-configuration 동작을 손댈 때는
WebFetch 로 공식 docs 를 먼저 확인하고 PR 본문에 verification line (`Verified against Spring Boot 4.0 § ... (YYYY-MM-DD)`) 을 남긴다.
Boot 3 → 4 점프 시 Jakarta namespace (`jakarta.persistence.*`, `jakarta.servlet.*`) 가 강제이므로 `javax.*` import 는 BLOCKING.

## 같이 보는 스킬

- [`SKILL.md`](SKILL.md) — Claude 가 실제로 읽는 본문
- [`../../../workflows/skills/coding-principles/SKILL.md`](../../../workflows/skills/coding-principles/SKILL.md) — 상위 stack-agnostic 코딩 원칙
- [`../data-access/SKILL.md`](../data-access/SKILL.md) — JPA·`JdbcClient`·Flyway 마이그레이션 세부 규칙
- [`../testing-kotlin/SKILL.md`](../testing-kotlin/SKILL.md) — JUnit 5·MockK·Testcontainers 테스트 규약
