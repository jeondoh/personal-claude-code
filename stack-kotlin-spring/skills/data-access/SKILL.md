---
name: data-access
description: Data access patterns for Kotlin + Spring Boot — JPA/Hibernate, JdbcClient, transactions, migrations, and query patterns. Use whenever Persistence Paladin writes or reviews repository code, ORM mappings, or DB migrations. Roastmaster's data-access bar enforces what's here.
---

# Data Access — Kotlin + Spring Boot

This skill is the bar for any DB-touching code. Companion skills - `kotlin-spring-boot-core` (Clean Architecture + layering), `testing-kotlin` (real-DB tests), `coding-principles` (general).

**Where this code lives**: per `kotlin-spring-boot-core` Clean Architecture, repository **interfaces** are declared in the `application/` layer (framework-free signatures using domain types). Everything in *this* skill — JPA mappings, `JdbcClient` calls, Flyway migrations, transaction boundaries — describes the `infrastructure/` side that **implements** those interfaces. JPA `@Entity` classes live in `infrastructure/`, not `domain/`; map between JPA entities and domain entities at the repository boundary.

**Precedence**: when this skill agrees with `kotlin-spring-boot-core` or `coding-principles`, follow them. When they diverge, this skill wins for data-access code.

## Choosing the access layer

| Need | Use | Why |
|---|---|---|
| Standard CRUD on aggregates with relations | Spring Data JPA + Hibernate | mapping reuse, repository abstraction |
| Read-heavy queries with shape that doesn't match aggregates | `JdbcClient` (Spring 6) | direct SQL, predictable performance, no entity hydration cost |
| Reactive / non-blocking | R2DBC | when the entire request path is reactive — don't mix with blocking JPA in same module |
| Bulk operations | `JdbcClient` or native `EntityManager` | JPA's `saveAll` does N round trips; use batched SQL |

Default: JPA for write paths, `JdbcClient` for reporting/list endpoints. Document the choice in the Design Doc.

## JPA / Hibernate rules

### Entity design

- **Don't use `data class` for JPA entities.** Auto-generated `equals`/`hashCode`/`toString` walk lazy proxies via `@OneToMany`/`@ManyToOne` and recurse to OOM. Use plain `class` and override `equals`/`hashCode` to compare only the surrogate ID. BLOCKING when violated.
- Constructors with required fields only; optional fields via property setters with `var` only if persistence requires. The `kotlin("plugin.jpa")` plugin synthesizes a no-arg constructor and `allOpen` opens entity classes — do **not** add `open` or a no-arg constructor manually.
- Surrogate `Long` or `UUID` IDs. Avoid composite primary keys unless DB design demands.
- `@Version` for optimistic locking on aggregates with concurrent writers.
- `@Embedded` for value objects; one-table-per-aggregate-root.

### Fetch strategy

- Default to **LAZY** for `@OneToMany`, `@ManyToMany`, `@ManyToOne`. Eager fetch is a foot-gun.
- Resolve N+1 via:
  - `@EntityGraph` on the repository method, **or**
  - explicit `JOIN FETCH` in JPQL, **or**
  - separate query that loads children by parent ids (most flexible for paginated lists).
- Roastmaster auto-flags any service-layer loop that calls `entity.getRelation()` without a fetch plan. N+1 is BLOCKING.

### Query patterns

- Spring Data derived queries (`findByEmail`, `findAllByStatusIn`) for simple cases.
- `@Query("SELECT ... FROM Entity ...")` JPQL for joins, projections, aggregations.
- Native SQL (`@Query(value = "...", nativeQuery = true)`) only when JPQL cannot express the query (e.g., DB-specific window functions). Document why.
- Projections (interface-based or DTO `select new`) for read endpoints — don't hydrate full entities for response payloads.

### Pagination

- `Pageable` parameter on list endpoints. Always.
- `Page<T>` for total-count responses (issues a count query). `Slice<T>` when count is unnecessary (cheaper).
- Server-side max page size (e.g., 200). Reject larger requests at controller validation.

### Transactions

- `@Transactional` on `@Service` methods. Read paths: `(readOnly = true)`.
- Single transaction per use case. If a use case spans multiple aggregates, model it explicitly (saga, outbox, eventual consistency) — do not extend the transaction across remote calls.
- No transactions in `@RestController`, no transactions in `@Repository`.
- Detached entities returned from a service must not be mutated by callers expecting auto-flush — return DTOs from service layer to the controller.

## JdbcClient (Spring 6)

**Spring 6+ prefers `JdbcClient` over the legacy `JdbcTemplate` / `NamedParameterJdbcTemplate`.** New code uses `JdbcClient` (the unified fluent API). Existing `JdbcTemplate` code is migrated opportunistically when touched.

For SQL-first access (reads, bulk):

```kotlin
val jdbc: JdbcClient
val users = jdbc.sql("SELECT id, email FROM users WHERE org_id = :orgId")
    .param("orgId", orgId)
    .query(UserSummary::class.java)
    .list()
```

- Always parameterized. String-concatenated SQL is BLOCKING (SQL injection).
- Map to a DTO/data class, not an entity. Keeps the JPA persistence context clean.
- Bulk insert: `jdbc.sql(...).batchUpdate(rows)` — single round trip for many rows.

## Migrations

- Flyway. Versioned migrations under `src/main/resources/db/migration/V<NNNN>__<slug>.sql`.
- One migration per logical change. Never modify a merged migration; add a new one.
- **Forward-only** — no `down()`. Rollback is a new forward migration.
- **`outOfOrder=false`** (Flyway default). Out-of-order application is BLOCKING — a `V0010__...` created after `V0011__...` is already deployed diverges from version control. Never enable `outOfOrder=true`.
- Schema changes that break in-flight reads (column rename, type change) require a 2-step migration:
  1. Add new column / table. Backfill. Deploy code that writes both.
  2. After verification, drop old. Deploy code that reads only new.
- Auto-large trigger (see `orchestration-guide`): any DDL migration → escalate to `large`.

## Common smells (Roastmaster blocks on)

- String-concatenated SQL.
- `findAll()` on a table that can grow unboundedly.
- N+1 query pattern in service-layer iteration.
- `@Transactional` opened on a controller.
- Migration script that mutates production data without an idempotency check.
- Native query referencing a column or table that does not exist in the current schema (AI hallucination — caught by integration test against real DB; if no real-DB test exists, BLOCKING per `testing-principles`).
- Repository method returning a `MutableList` or a Hibernate proxy across the service boundary.
- Using `.flush()` or `.clear()` to "fix" stale state — symptom of a deeper transaction-boundary problem.

## Caching

- Local cache (Caffeine) for read-mostly reference data (currencies, country codes).
- Distributed cache (Redis) for cross-instance shared state.
- Always set TTL. Cache invalidation strategy must be in the Design Doc — "cache forever" is never the answer.
- Don't cache entities (lazy-loading + serialization is a trap). Cache projections.

## Connection pool

- HikariCP defaults are sane; tune `maximum-pool-size` based on `(cores × 2) + effective_spindle_count` rule of thumb, then measure.
- Slow queries log threshold set in `application.yml`. Pin to 1s by default; tune per environment.

## When this skill conflicts with the AC

Data-access AC waivers (e.g., "use raw JDBC for this performance-critical path") are accepted when documented in Design Doc with measurement justifying the deviation. Otherwise, follow this skill.
