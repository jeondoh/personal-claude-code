---
name: kotlin-spring-boot-core
description: Kotlin idioms and Spring Boot conventions for backend code in this team. Use when Persistence Paladin (or any persona) writes or reviews Kotlin + Spring Boot code. Layered on top of the stack-agnostic coding-principles skill — read that first, then apply these stack-specific rules.
---

# Kotlin + Spring Boot — Core

Stack-specific overlay on `coding-principles`. When this skill and `coding-principles` agree, follow `coding-principles`. When they diverge, this skill wins for Kotlin/Spring code.

## Version handling — detect, don't assume

This skill applies to **whichever versions are actually installed in the project**, not a fixed pin. The values in the reference table below were observed at skill authoring time (2026-05); the real source of truth is `build.gradle.kts`. Worker MUST detect first, then verify against official docs when the installed version is outside training-data confidence.

### Reference (skill authoring snapshot, not a mandate)

| Item | Reference | Detect from |
|---|---|---|
| JDK | 24 | `build.gradle.kts` → `java.toolchain.languageVersion` |
| Kotlin | 2.2+ | `build.gradle.kts` → `kotlin("jvm") version "..."` |
| Spring Boot | 4+ | `build.gradle.kts` → `id("org.springframework.boot") version "..."` |
| Build | Gradle Kotlin DSL (convention) | (project convention) |

Library coordinates (Spring starters, JDBC drivers, JSON modules, test runners) are **not pinned** at the workflow level — pick what each ticket needs and verify per protocol below.

### Protocol (BLOCKING when violated)

1. **Detect** Spring Boot, Kotlin, JDK from `build.gradle.kts` at the start of work. Record in design notes or PR description.
2. **Compare to training cutoff**. Evergreen content in this skill (entity rules, immutability, `allOpen` + JPA semantics, transactional boundaries, layering, security defaults — *as concepts*) applies broadly across recent majors.
3. **If the installed version is newer than your confident training** OR you are about to add a starter coordinate, choose a config key, use a Spring Framework API, or rely on auto-configuration behavior: **MUST verify via official docs before writing code**.
   - Spring Boot reference: https://docs.spring.io/spring-boot/reference/
   - Spring Framework reference: https://docs.spring.io/spring-framework/reference/
   - Kotlin docs: https://kotlinlang.org/docs/
   - Use the WebFetch tool to fetch the specific section.
4. **Particularly version-volatile** (always re-verify): starter artifact names (many moved across Boot 3 → 4), property keys under `spring.*` (renamed/relocated between versions), auto-configuration toggles, Kotlin compiler args (Kotlin 2.x introduced new defaults; check before adding `-X` flags).
5. **Boot 3 → 4 specifically**: Jakarta migration is complete on 4 (`jakarta.persistence.*`, `jakarta.servlet.*`). `javax.*` is forbidden on 4+. Many starters were renamed. If installed Boot is 4+ **always cross-check against current Spring Boot 4 docs**, do not trust Boot 3 knowledge.
6. **Never invent** starter coordinates, property keys, plugin IDs, or default behaviors from training data. When uncertain, WebFetch → read → code. If docs are ambiguous, escalate via `inbox/` rather than guess.
7. **Record verification** in PR description: e.g., `Verified against Spring Boot 4.0 § Data Access (2026-05-11)`. Roastmaster & codex use this to scope their review.

### Kotlin compiler args — verify before applying

The args below were standard at skill authoring time but Kotlin major bumps can change defaults. Verify against `https://kotlinlang.org/docs/compiler-reference.html` for the installed Kotlin version before adding to `build.gradle.kts`.

```kotlin
// Verify these still exist and have the documented semantics for your Kotlin version.
freeCompilerArgs.addAll("-Xjsr305=strict", "-Xannotation-default-target=param-property")
```

- `-Xjsr305=strict` — treat external nullability annotations strictly.
- `-Xannotation-default-target=param-property` — Kotlin 2.2 default for annotations on constructor params; avoids the param-vs-property surprise on JPA + validation annotations. **If installed Kotlin ≥ 2.3, check whether this is now default-on and the flag is obsolete.**

**JPA + `allOpen` rule (entity authoring)**: the `kotlin("plugin.jpa")` plugin auto-applies `allOpen` for `jakarta.persistence.{Entity, MappedSuperclass, Embeddable}`. Workers do **not** add `open` keyword manually and do **not** write a no-arg constructor manually — both are synthesized.

Entity rules (BLOCKING when violated; reinforced by `data-access`):

- **Don't use `data class` for JPA entities.** Auto-generated `equals`/`hashCode` walk lazy proxies and recurse to OOM. Use plain `class` with equals/hashCode based on the surrogate ID only.
- **Don't add `open`** to entity classes — `allOpen` plugin does it.
- **Don't write a no-arg constructor** — `kotlin("plugin.jpa")` synthesizes it.

## Kotlin idioms

### Nullability

- Public APIs: avoid `?`-typed parameters and return values. Use overloads or default values instead.
- Internal: `?` is fine when "absent" is genuinely a domain state. `lateinit` only for DI-injected fields where construction order forbids constructor injection.
- `!!` is forbidden in production code. If you genuinely need to assert non-null, use `requireNotNull(x) { "<context>" }` so the failure carries context.
- `?.let { }` for optional side effects; do not nest more than 2 deep.

### Data classes vs classes vs `value class`

- DTOs, request/response, domain values without behavior → `data class`.
- Domain entities with invariants → `class` with private constructor + factory or `init` block.
- Single-property wrappers carrying type-level meaning (`UserId`, `Email`) → `@JvmInline value class`.

### Immutability

- `val` over `var` always. `var` only inside narrow function-local scope.
- `List<T>` (read-only) for parameters and return types. `MutableList<T>` only inside a function.
- Collections returned from public APIs are read-only views.

### Functions

- Top-level functions for stateless operations. Don't make a class just to hold static helpers.
- Extension functions for adding domain-specific verbs to existing types — use sparingly; prefer regular functions when the receiver is yours.
- `inline fun` for higher-order functions on hot paths only. Profile before inlining.

### Coroutines

- Suspending functions for I/O and async coordination. Spring 6 / Boot 4 supports coroutines on controllers.
- Structured concurrency: every coroutine runs inside a `coroutineScope { }` or a Spring-provided scope. No `GlobalScope`.
- `Dispatchers.IO` for blocking JDBC / file I/O. `Dispatchers.Default` for CPU-bound. Don't use `Dispatchers.Main` server-side.
- `runBlocking` only in `main` and tests. Never in production request handlers.
- **`@Transactional` does not propagate across coroutine context switches.** Spring's transaction state is thread-local; `withContext(Dispatchers.IO)` switches threads and loses it. Patterns:
  - For suspending controllers, place `@Transactional` on the suspending service method and let Spring's coroutine-aware tx manager keep it attached.
  - When you need `withContext(Dispatchers.IO)` for blocking JDBC inside a service call, keep the entire DB conversation **inside one transactional boundary** — do not span the boundary across the dispatcher switch.
  - BLOCKING: `@Transactional` outside a `withContext(Dispatchers.IO)` block that contains the JDBC calls — the IO dispatcher loses thread-local tx state and writes commit on the wrong boundary.

## Spring Boot conventions

### Architecture — Clean Architecture (simple)

We use a **simple Clean Architecture** — not full hexagonal. Four layers, dependencies point inward toward `domain`:

```
api  →  application  →  domain  ←  infrastructure
                                   (implements interfaces declared in application)
```

| Layer | Responsibility | May depend on | Must NOT depend on |
|---|---|---|---|
| `api` | HTTP/JSON only — request mapping, validation, error envelope. No business logic. | `application` (services) | `domain` directly, `infrastructure` |
| `application` | Use cases. One `@Service` ≈ one user story. Orchestrates domain + repository **interfaces**. | `domain`, repository interfaces it declares itself | `infrastructure`, `api` |
| `domain` | Pure Kotlin. Entities, value objects, domain services. Framework-free. | nothing in this codebase | everything else |
| `infrastructure` | Concrete adapters — JPA repositories, external HTTP clients, file/queue I/O. **Implements** interfaces from `application`. | `application` (interfaces), `domain` (entities/values) | `api` |

**Dependency Inversion (DIP)** — repository interfaces are declared **in the `application` layer** (e.g., `application/UserRepository.kt`); the JPA implementation lives in `infrastructure` (e.g., `infrastructure/persistence/JpaUserRepository.kt`) and is wired by Spring DI. This is the only abstraction we add — we deliberately do **not** introduce hexagonal Ports/Adapters or use-case Interactor classes. Keep it boring.

**BLOCKING patterns Roastmaster rejects:**
- `import org.springframework.*` (or any framework import) inside `domain/`
- `application` directly importing a concrete class from `infrastructure/` (interface-only DIP violation)
- `api` calling `infrastructure` and skipping `application`
- Repository interface declared inside `infrastructure/` (must live in `application/`)

### Dependency injection

- Constructor injection always. No `@Autowired` on fields.
- `@Service`, `@Repository`, `@RestController`, `@Configuration` — use the most specific stereotype.
- `@Component` only when none of the above applies.
- Configuration via `@ConfigurationProperties` data class, validated with `@Validated`.

### Configuration

- `application.yml` (not `.properties`) for hierarchical config.
- Profiles for environment differences (`application-dev.yml`, `application-test.yml`).
- Secrets via env var or vault, not in YAML. Use `${VAR_NAME}` placeholders.
- `@ConfigurationProperties` over `@Value` — type-safe, testable, refactorable.

### Web layer

- `@RestController` for JSON APIs. `@Controller` for server-rendered pages (rare in this codebase).
- Request/response classes are `data class` records, not entities. Map between layers explicitly.
- Validation with `@Valid` + `jakarta.validation` annotations on the DTO.
- Error handling via a single `@RestControllerAdvice` that maps exceptions to a uniform error envelope (`{ error: { code, message, details } }`). No exception leaks raw stack traces to clients.

### Logging

- SLF4J via Kotlin Logging (`KotlinLogging.logger {}`).
- Structured logging where possible (key-value pairs in MDC).
- Log levels:
  - `error` — actionable: someone or something must respond.
  - `warn` — degraded but handled.
  - `info` — milestone events (startup, shutdown, request received at boundary).
  - `debug` — verbose, off in prod.
- Never log secrets, full request bodies of unbounded size, or full stack traces of expected business exceptions (e.g., validation failures).

### Transactions

- `@Transactional` on the service method, not on the controller or the repository.
- Default propagation `REQUIRED`, default isolation `READ_COMMITTED`.
- Read-only operations: `@Transactional(readOnly = true)` — enables JPA optimizations.
- See `data-access` skill for transaction boundary details and N+1 prevention.

## Project structure

```
src/main/kotlin/<root-package>/
├── <bounded-context>/
│   ├── api/              # @RestController + request/response DTOs
│   ├── application/      # @Service (use cases) + repository INTERFACES
│   ├── domain/           # framework-free entities, value objects, domain services
│   └── infrastructure/   # @Repository implementations, external HTTP clients, JPA entities
├── common/               # cross-context utilities, error envelope, base config
└── Application.kt        # @SpringBootApplication entry point
```

One bounded context per package directly under root. Cross-context calls go through `application` services, never directly into another context's `domain` or `infrastructure`.

Repository contract example (DIP in practice):
```kotlin
// application/UserRepository.kt — interface only, framework-free signatures
interface UserRepository {
    fun findById(id: UserId): User?
    fun save(user: User): User
}

// infrastructure/persistence/JpaUserRepository.kt — Spring-aware implementation
@Repository
class JpaUserRepository(private val jpa: SpringDataUserRepository) : UserRepository { ... }
```

## Build and tooling

- Gradle Kotlin DSL (`build.gradle.kts`) — not Groovy.
- Kotlin / Spring Boot / JDK pinned per the **Versions (pinned)** table at the top of this file. Toolchain config in `build.gradle.kts`.
- Spring Boot `BOM` for transitive dependency versions.
- ktlint or detekt configured; pre-commit hook runs both. Format errors fail CI.
- JVM target matches the deployed JDK (no version drift between local and prod).

### Canonical commands (rescue trigger matches on these)

- `./gradlew build` — compile + test + checks (full verification).
- `./gradlew test` — tests only.
- `./gradlew test --tests "<FQCN>"` — single class.
- `./gradlew test --tests "<FQCN>.<method>"` — single method.
- `./gradlew ktlintCheck` (or detekt equivalent) — lint only.

The `error_signature` calculation in `adversarial-review-bridge` depends on these commands' error output format — do not deviate without updating the bridge skill.

## Performance smells (Roastmaster blocks on)

- N+1 queries in JPA — see `data-access`.
- `@Transactional` on a controller method.
- Blocking JDBC inside a coroutine without `Dispatchers.IO`.
- Mutable list returned from a public service method.
- `runBlocking` outside main/tests.
- Reflection-based serialization in hot paths (use kotlinx.serialization or jackson-kotlin with sane defaults).

## When this skill conflicts with the AC

If an AC explicitly demands a deviation (e.g., "use Java for this module due to legacy constraint"), document the deviation in the Design Doc and notify Roastmaster in advance. AC waivers are in-scope for stack overlays.
