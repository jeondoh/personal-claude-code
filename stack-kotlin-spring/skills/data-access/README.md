# data-access

Kotlin + Spring Boot DB 코드에 적용되는 JPA·`JdbcClient`·트랜잭션·Flyway 마이그레이션 규약.

## 무엇을 하나

이 스킬은 DB 를 건드리는 모든 코드의 품질 바다.
`kotlin-spring-boot-core` 의 Clean Architecture 를 전제로, repository 인터페이스는 `application/` 에 두고
JPA 매핑·`JdbcClient` 호출·Flyway 스크립트는 `infrastructure/` 에 둔다는 boundary 를 강제한다.

엔티티 `data class` 금지·LAZY default·N+1 차단·forward-only 마이그레이션·string-concatenated SQL BLOCKING 같은 룰을 한 곳에 모은다.
주 사용자는 Persistence Paladin 이고, Roastmaster 의 data-access 바도 이 파일이 정본이다.

## 언제 작동하나

Persistence Paladin 이 repository 코드·ORM 매핑·DB 마이그레이션을 작성하거나 리뷰할 때 활성화된다.
JPA·JdbcClient·R2DBC 중 어떤 access layer 를 골라야 할지 판단할 때도 이 스킬의 decision table 을 본다.

## 다루는 주제

- Access layer 선택 (JPA vs `JdbcClient` vs R2DBC vs bulk SQL)
- JPA 엔티티 설계 룰 (`data class` 금지, surrogate ID, `@Version` 낙관 락, `@Embedded` value object)
- Fetch strategy 와 N+1 회피 (`@EntityGraph` / `JOIN FETCH` / separate-query)
- Query 패턴·페이지네이션 (`Pageable`, `Page` vs `Slice`, server-side max page size)
- 트랜잭션 경계 (`@Service` 에만, `readOnly` 옵션, saga/outbox 로 cross-aggregate 처리)
- `JdbcClient` (Spring 6+ 의 권장 SQL-first API) 사용법과 batch update
- Flyway 마이그레이션 (versioned, forward-only, 2-step rename, `outOfOrder=false`)
- 캐싱 (Caffeine / Redis, TTL 필수)·HikariCP 튜닝
- Roastmaster 가 블록하는 smell 목록 (concat SQL·unbounded `findAll`·controller transaction)

## 정본 (Source of Truth)

설치된 Spring Boot / Hibernate / Flyway / 드라이버 버전은 `build.gradle.kts` 가 정본이다.
Boot 3 → 4 점프 시 Jakarta namespace (`jakarta.persistence.*`) 와 starter 좌표가 바뀌었으므로,
training cutoff 보다 새로운 메이저에서는 WebFetch 로 Spring Data·Hibernate·Flyway 공식 docs 를 확인한 뒤 코드를 쓴다.

DDL 마이그레이션이 포함된 ticket 은 `orchestration-guide` 의 auto-large 트리거에 걸려 자동으로 large complexity 로 escalation 된다.

## 같이 보는 스킬

- [`SKILL.md`](SKILL.md) — Claude 가 실제로 읽는 본문
- [`../kotlin-spring-boot-core/SKILL.md`](../kotlin-spring-boot-core/SKILL.md) — Clean Architecture·layer 룰 (이 스킬의 전제)
- [`../testing-kotlin/SKILL.md`](../testing-kotlin/SKILL.md) — `@DataJpaTest` + Testcontainers 로 repository 검증 (H2 금지)
- [`../../../workflows/skills/coding-principles/SKILL.md`](../../../workflows/skills/coding-principles/SKILL.md) — 상위 stack-agnostic 코딩 원칙
