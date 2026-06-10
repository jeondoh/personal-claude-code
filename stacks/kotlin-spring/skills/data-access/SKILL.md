---
name: data-access
description: Data access patterns for Kotlin + Spring Boot — JPA/Hibernate, JdbcClient, transactions, migrations, and query patterns. Use whenever Persistence Paladin writes or reviews repository code, ORM mappings, or DB migrations. Roastmaster's data-access bar enforces what's here.
---

# Data Access — Kotlin + Spring Boot

The bar for DB-touching code. Companion - `kotlin-spring-boot-core` (Clean Architecture + layering), `testing-kotlin` (real-DB tests), `coding-principles`.

**Layering** (per `kotlin-spring-boot-core`): repository **interfaces** live in `application/` (framework-free, domain types). This skill is the `infrastructure/` side that **implements** them — JPA mappings, `JdbcClient`, Flyway, tx boundaries. JPA `@Entity` lives in `infrastructure/`, not `domain/`; map JPA↔domain at the repository boundary.

**Precedence**: follow `kotlin-spring-boot-core` / `coding-principles` where they agree; this skill wins for data-access where they diverge.

## Choosing the access layer

Default: **JPA + Querydsl**. `JdbcClient` is opt-in for hot-path read or bulk where Querydsl was *measured* insufficient — document the measurement in the Design Doc or ADR.

| Need | Use |
|---|---|
| Standard CRUD on aggregates with relations | Spring Data JPA + Hibernate |
| Dynamic queries (variable predicates/sorts/projections) | Querydsl (`JPAQueryFactory`) — type-safe, refactor-safe |
| Read-heavy queries not matching aggregates | Querydsl projection first; `JdbcClient` (Spring 6) only when measurement shows it matters |
| Reactive / non-blocking | R2DBC — only when entire request path is reactive; never mix with blocking JPA in same module |
| Bulk operations | JPA batched (`saveAll` + `hibernate.jdbc.batch_size`) → Querydsl batch → `JdbcClient` last resort |

## JPA / Hibernate rules

### Entity design

- **No `data class` for JPA entities** — BLOCKING. Auto-generated `equals`/`hashCode`/`toString` walk lazy proxies and recurse to OOM. Use plain `class`; override `equals`/`hashCode` to compare only the surrogate ID.
- Constructors take required fields only; optional via property setters, `var` only if persistence requires. `kotlin("plugin.jpa")` synthesizes the no-arg constructor and `allOpen` opens entities — do **not** add `open` or a no-arg constructor manually.
- Surrogate `Long` or `UUID` IDs. Avoid composite primary keys unless DB design demands.
- `@Version` for optimistic locking on aggregates with concurrent writers.
- `@Embedded` for value objects; one-table-per-aggregate-root.

### Fetch strategy

- **LAZY** by default for `@OneToMany`, `@ManyToMany`, `@ManyToOne`. Eager is a foot-gun.
- Resolve N+1 via `@EntityGraph` on the repository method, explicit `JOIN FETCH` in JPQL, or a separate query loading children by parent ids (most flexible for paginated lists).
- N+1 is BLOCKING — Roastmaster auto-flags any service-layer loop calling `entity.getRelation()` without a fetch plan.

### Query patterns

- Spring Data derived queries (`findByEmail`, `findAllByStatusIn`) for simple cases.
- `@Query("SELECT ... FROM Entity ...")` JPQL for joins, projections, aggregations.
- Native SQL (`@Query(value = "...", nativeQuery = true)`) only when JPQL **and Querydsl** both can't express it (e.g., DB-specific window functions). Document why.
- Projections (interface-based or DTO `select new`) for read endpoints — don't hydrate full entities for response payloads.

### Querydsl (dynamic queries)

Required when: predicates depend on optional inputs (filters/search/admin lists); projections target per-endpoint DTOs; joins compose conditionally.

- One `JPAQueryFactory` bean in `infrastructure/QuerydslConfig.kt`. Inject into repository impls only — never `application/` or `domain/`.
- Generated Q-types in `build/generated/` — exclude from coverage and ArchUnit scans.
- Projections via `Projections.constructor(DtoClass::class.java, ...)` (or `bean(...)` when a no-arg constructor is required). Don't hydrate full entities for reads.
- Pagination: pair Querydsl `OrderSpecifier` with the same `Pageable` contract — `PageableExecutionUtils.getPage(content, pageable) { countQuery.fetchOne() ?: 0 }`.

**Not** Querydsl: single-static-predicate query → Spring Data derived method. Hot-path read where Querydsl SQL is measurably worse → `JdbcClient` with a Design Doc / ADR note (see §JdbcClient).

### Pagination

- `Pageable` parameter on list endpoints — always.
- `Page<T>` for total-count responses (issues a count query); `Slice<T>` when count is unnecessary (cheaper).
- Server-side max page size (e.g., 200). Reject larger requests at controller validation.

### Transactions

- `@Transactional` on `@Service` methods; read paths `(readOnly = true)`.
- Single transaction per use case. Spanning multiple aggregates → model explicitly (saga, outbox, eventual consistency); never extend the transaction across remote calls.
- No transactions in `@RestController` or `@Repository`.
- Return DTOs from service to controller — detached entities must not be mutated by callers expecting auto-flush.

## JdbcClient (Spring 6)

**Spring 6+ prefers `JdbcClient` over legacy `JdbcTemplate` / `NamedParameterJdbcTemplate`.** New code uses `JdbcClient`; existing `JdbcTemplate` migrated opportunistically when touched. For SQL-first access (reads, bulk):

```kotlin
val jdbc: JdbcClient
val users = jdbc.sql("SELECT id, email FROM users WHERE org_id = :orgId")
    .param("orgId", orgId)
    .query(UserSummary::class.java)
    .list()
```

- Always parameterized. String-concatenated SQL is BLOCKING (SQL injection).
- Map to a DTO/data class, not an entity — keeps the persistence context clean.
- Bulk insert: `jdbc.sql(...).batchUpdate(rows)` — single round trip.

## Migrations

- Flyway. Versioned migrations under `src/main/resources/db/migration/V<NNNN>__<slug>.sql`.
- One migration per logical change. Never modify a merged migration; add a new one.
- **Forward-only** — no `down()`. Rollback is a new forward migration.
- **`outOfOrder=false`** (Flyway default) — BLOCKING to enable. A `V0010__...` created after `V0011__...` is deployed diverges from version control.
- Schema changes breaking in-flight reads (column rename, type change) require a 2-step migration:
  1. Add new column/table, backfill, deploy code writing both.
  2. After verification, drop old, deploy code reading only new.
- Auto-large trigger (see `orchestration-guide`): any DDL migration → escalate to `large`.

## Common smells (Roastmaster blocks on)

- String-concatenated SQL.
- `findAll()` on an unboundedly growing table.
- N+1 in service-layer iteration.
- `@Transactional` on a controller.
- Migration mutating production data without an idempotency check.
- Native query referencing a column/table absent from current schema (AI hallucination — caught by integration test against real DB; no real-DB test → BLOCKING per `testing-principles`).
- Repository method returning `MutableList` or a Hibernate proxy across the service boundary.
- `.flush()`/`.clear()` to "fix" stale state — symptom of a deeper transaction-boundary problem.

## Caching

- Caffeine (local) for read-mostly reference data (currencies, country codes); Redis (distributed) for cross-instance shared state.
- Always set TTL. Invalidation strategy goes in the Design Doc — "cache forever" is never the answer.
- Cache projections, not entities (lazy-loading + serialization is a trap).

## Connection pool

- HikariCP defaults are sane; tune `maximum-pool-size` from `(cores × 2) + effective_spindle_count`, then measure.
- Slow-query log threshold in `application.yml`. Default 1s; tune per environment.

## When this skill conflicts with the AC

Data-access AC waivers (e.g., "use raw JDBC for this performance-critical path") are accepted when documented in the Design Doc with measurement justifying the deviation. Otherwise, follow this skill.
