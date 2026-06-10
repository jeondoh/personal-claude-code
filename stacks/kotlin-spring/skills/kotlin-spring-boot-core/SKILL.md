---
name: kotlin-spring-boot-core
description: Kotlin idioms and Spring Boot conventions for backend code in this team. Use when Persistence Paladin (or any persona) writes or reviews Kotlin + Spring Boot code. Layered on top of the stack-agnostic coding-principles skill — read that first, then apply these stack-specific rules.
---

# Kotlin + Spring Boot — Core

Stack overlay on `coding-principles`. On conflict, this skill wins for Kotlin/Spring code.

**The bar:** rich domain · thin controllers · narrow exceptions · declarative cross-cutting.

Every rule is **BLOCKING** unless tagged `(SHOULD)`. Roastmaster auto-rejects PRs violating a BLOCKING rule.

## Version handling — detect, don't assume

Snapshot observed at authoring time (2026-05). Source of truth is `build.gradle.kts`.

| Item | Snapshot | Detect from |
|---|---|---|
| JDK | 24 | `java.toolchain.languageVersion` |
| Kotlin | 2.2+ | `kotlin("jvm") version "..."` |
| Spring Boot | 4+ | `id("org.springframework.boot") version "..."` |
| Build | Gradle Kotlin DSL | (convention) |

### Protocol

1. **Detect** Boot / Kotlin / JDK from `build.gradle.kts` at start of work; record in design notes or PR description.
2. **Verify before writing** when (a) installed version is newer than confident training, or (b) adding a starter coordinate, choosing a config key, using a Spring Framework API, or relying on auto-configuration. WebFetch:
   - https://docs.spring.io/spring-boot/reference/ · https://docs.spring.io/spring-framework/reference/ · https://kotlinlang.org/docs/
3. **Volatile across majors** (always re-verify): starter artifact names, `spring.*` keys, auto-config toggles, Kotlin compiler args. **Boot 4+** is Jakarta-only — `javax.*` forbidden; do not trust Boot 3 knowledge against Boot 4 code.
4. **Never invent** starter coordinates, property keys, plugin IDs, or default behaviors. Uncertain → WebFetch. Ambiguous → escalate via `inbox/`.
5. **Record** in PR description: `Verified against Spring Boot 4.0 § Data Access (2026-05-11)`.

### Kotlin compiler args

```kotlin
freeCompilerArgs.addAll("-Xjsr305=strict", "-Xannotation-default-target=param-property")
```

- `-Xjsr305=strict` → strict external-nullability annotations.
- `-Xannotation-default-target=param-property` → Kotlin 2.2 default for constructor-param annotations (resolves param-vs-property on JPA/validation). For Kotlin ≥ 2.3 verify whether it's now default-on and obsolete.

### JPA + `allOpen`

`kotlin("plugin.jpa")` auto-applies `allOpen` for `jakarta.persistence.{Entity, MappedSuperclass, Embeddable}` and synthesizes the no-arg constructor. **Do not** add `open` or a no-arg constructor manually. **`data class` for JPA entity is forbidden** — auto `equals`/`hashCode` walks lazy proxies → OOM. Plain `class`; `equals`/`hashCode` on surrogate ID only. (Reinforced by `data-access`.)

## Architecture — Clean Architecture (simple)

Four layers; dependencies point inward toward `domain`. No hexagonal Ports/Adapters, no Interactor classes.

```
api  →  application  →  domain  ←  infrastructure
                                   (implements interfaces declared in application)
```

| Layer | Owns | May depend on | Forbidden |
|---|---|---|---|
| `api` | HTTP/JSON shape, validation, error envelope | `application` | `domain` direct, `infrastructure` |
| `application` | Use cases, transactions, repo orchestration, mapping | `domain`, repo interfaces declared here | `infrastructure`, `api` |
| `domain` | Entities, value objects, domain services, sealed errors. Framework-free. | nothing | everything else |
| `infrastructure` | JPA repos, HTTP clients, file/queue, aspects, filters | `application` interfaces, `domain` | `api` |

**Dependency Inversion (DIP).** Repository interfaces in `application/` (framework-free); JPA implementations in `infrastructure/`; Spring DI wires them.

```kotlin
interface UserRepository { fun findById(id: UserId): User?; fun save(user: User): User }   // application/
@Repository class JpaUserRepository(private val jpa: SpringDataUserRepository) : UserRepository { /* ... */ }   // infrastructure/
```

### BLOCKING — layer crimes

- **`api/`** — calls `@Repository` directly; catches domain exceptions to shape responses (advice does it); builds aggregates by hand instead of via domain factory; reads/writes `MDC`; branches that encode business rules.
- **`application/`** — computes business invariants (that's on the entity); holds mutable state; catches generic `Exception` "to be safe"; calls another bounded context's `domain/` or `infrastructure/` directly.
- **`domain/`** — imports Spring / JPA / Jackson / anything from `infrastructure/`; performs I/O including logging; exposes public setters (other than JPA-forced `var`).
- **`infrastructure/`** — imports from `api/`; returns JPA `@Entity` or Hibernate proxy across the interface boundary (map at boundary); lets `SQLException`/`IOException`/`HttpClientErrorException` leak upward (translate to sealed domain error).
- **Cross-cutting** — repository interface declared in `infrastructure/` (must live in `application/`); cross-context call into another context's `domain/` or `infrastructure/` (must go through that context's `application/`).

## Domain modeling — rich, not anemic

The `domain` layer owns business rules. `@Service` orchestrates; it does not compute.

1. **Entities own their invariants.** `private constructor` + `companion object` factory (or `init`) that validates with `require`. No half-built entity escapes construction.
2. **Tell, don't ask.** If a service reads a field, mutates it, and writes back, the verb belongs on the entity. `user.activate()` not `user.status = ACTIVE`.
3. **No public setters on domain entities.** Mutation only through intention-revealing methods (`order.confirm()`, `account.withdraw(amount)`).
4. **Value objects for typed concepts.** `Email`, `Money`, `UserId` — `@JvmInline value class` for single field, `data class` for multi-field. Validate in `init`. Never pass raw `String`/`Long` for a typed concept across layer boundaries.
5. **Domain service is the last resort.** Reach for `domain/XxxPolicy.kt` only when the rule spans multiple aggregates and cannot live on either entity.
6. **`enum class`** for closed sets of identifiers (status, roles). **`sealed class`** when each variant carries different data or behavior.
7. **Time** through an injected `Clock`. Never `Instant.now()` / `LocalDateTime.now()` directly in domain or application code. Store `Instant` (UTC) at persistence; render local times only at the api edge.
8. **Money** as `BigDecimal` with explicit scale and `RoundingMode`, wrapped in a `Money` value object (currency + amount together).

```kotlin
// Entity owns the rule; service orchestrates.
class Order private constructor(/* ... */) {
    fun confirm(now: Instant) {
        check(status == PENDING) { "order $id is not pending" }
        check(lines.isNotEmpty()) { "order $id has no lines" }
        status = CONFIRMED; confirmedAt = now
    }
    companion object { fun create(/* ... */): Order { require(/* ... */); return Order(/* ... */) } }
}

@Service
class OrderService(private val repo: OrderRepository, private val clock: Clock) {
    @Transactional
    fun confirm(id: OrderId) {
        val order = repo.findById(id) ?: throw OrderError.NotFound(id)
        order.confirm(clock.instant()); repo.save(order)
    }
}
```

## DTO / Command / Query — explicit layer boundaries

Five DTO families. Do not collapse them.

| Crossing | Type | Naming | Lives in |
|---|---|---|---|
| HTTP → controller | Request | `<Verb><Noun>Request` | `api/` |
| controller → service (write) | Command | `<Verb><Noun>Command` | `application/` |
| controller → service (read) | Query | `<Noun>Query` | `application/` |
| service → controller (read) | View / Result | `<Noun>View` or `<Verb><Noun>Result` | `application/` |
| controller → HTTP | Response | `<Noun>Response` | `api/` |

1. **≥ 3 parameters on a public method (controller / service / repo interface) → introduce a Command/Query.** Two related primitives that always travel together (`email + password`) → group at count 2. Anti-patterns: `fun register(email, password, displayName, locale, marketingOptIn)`, `fun search(name?, status?, from?, to?, page, size)`.
2. **No `@Entity` on the HTTP wire.** Controllers neither accept nor return an entity; map at the api↔application boundary. `fun update(user: User)` on a controller is mass-assignment.
3. **CQS.** A Command returns `Unit` or the new aggregate's id. A Query is `readOnly = true` and returns a View. A method that mutates *and* returns a rich view — split it.
4. **DTOs are `data class`, immutable, framework-free** apart from Bean Validation on the Request. No JPA on Commands/Queries/Views.
5. **Mapping lives in `application/`** (or a dedicated `XxxMapper.kt`), never in `domain/`.
6. **No `Map<String, Any>` or anonymous data classes** to dodge the rule — that's a Command with no name; name it.

```kotlin
// api/UserController.kt — Request lives here; mapping at controller body.
data class RegisterUserRequest(
    @field:Email val email: String,
    @field:Size(min = 8) val password: String,
    @field:NotBlank val displayName: String,
)

@PostMapping("/users")
fun register(@Valid @RequestBody req: RegisterUserRequest): UserResponse =
    UserResponse.from(userService.register(RegisterUserCommand(Email(req.email), Password(req.password), req.displayName)))

// application/RegisterUserCommand.kt — typed Command, no JPA, no validation annotations.
data class RegisterUserCommand(val email: Email, val password: Password, val displayName: String)
```

## Exception handling

`try-catch` is forbidden in business logic. Exceptions propagate to `@RestControllerAdvice` — the single response-mapping site.

1. **No `try-catch` in `api/`, `application/`, `infrastructure/`** for control flow or wrap-and-rethrow. Validation → `require` / `check` / `requireNotNull` / `@Valid`. Business-rule violation → throw a sealed domain exception. Library exceptions (`DataAccessException`, `HttpClientErrorException`, etc.) propagate unwrapped — the advice has explicit handlers; `repository.save(...)` does **not** `try-catch` to translate.
2. **`try-catch` allowed only at four sites:**
   - `@RestControllerAdvice` mapping domain + library exceptions → error envelope.
   - **Filter chain** (Spring Security / servlet filters) — advice does not reach it; catch the narrowest framework exception inline (e.g. `JwtException`).
   - **Utility / helper functions** (parsers, mappers) encapsulating fallback-value semantics. The helper is the boundary — **never inside service / controller bodies**.
   - Resource cleanup — prefer `use { }` / `try-finally`.
3. **No generic catch.** `catch (e: Exception)` / `catch (e: Throwable)` is BLOCKING. Catch the narrowest type.
4. **No swallow.** `catch { }`, `catch { log.warn(...) }` without rethrow, `catch { return null }` without semantic justification.
5. **Business errors = `sealed class` rooted at a common `DomainException`.**
   - `common/error/DomainException.kt` → `sealed class DomainException(message, cause) : RuntimeException`.
   - Per bounded context: `sealed class XxxError(message, cause) : DomainException(message, cause)` (e.g. `AuthError`, `OrderError`).
   - Concrete cases: `class CaseName(...) : XxxError("...")`.
   - Plain `RuntimeException("...")` for business errors is BLOCKING.
6. **Single domain handler in advice.** `@ExceptionHandler(DomainException::class)` dispatches by exhaustive `when (e)` to per-context handlers. New bounded context = new `when` branch, no new `@ExceptionHandler`. Status code mapped here, not in service.
7. **`runCatching { }`** allowed only when (a) immediately mapped to a domain `Result`, (b) bridging non-Kotlin code with checked exceptions, or (c) inside utility helpers for fallback. Wrapping a whole service body is BLOCKING.
8. **No `@Throws` chains** across layers to simulate checked exceptions. KDoc the contract on public service methods when needed.

```kotlin
// common/error/DomainException.kt — root of business errors
sealed class DomainException(message: String, cause: Throwable? = null) : RuntimeException(message, cause)

// order/domain/OrderError.kt
sealed class OrderError(message: String, cause: Throwable? = null) : DomainException(message, cause) {
    class NotFound(val id: OrderId)         : OrderError("order $id not found")
    class AlreadyConfirmed(val id: OrderId) : OrderError("order $id already confirmed")
    class EmptyOrder(val id: OrderId)       : OrderError("order $id has no lines")
}

// auth/domain/AuthError.kt
sealed class AuthError(message: String, cause: Throwable? = null) : DomainException(message, cause) {
    class EmailAlreadyExists(val email: String) : AuthError("email already exists: $email")
    class InvalidCredentials                    : AuthError("invalid credentials")
}

// api/GlobalExceptionHandler.kt — single domain handler dispatched by when
@RestControllerAdvice
class GlobalExceptionHandler {
    @ExceptionHandler(DomainException::class)
    fun handleDomain(e: DomainException): ResponseEntity<ErrorEnvelope> = when (e) {
        is OrderError -> handleOrder(e)
        is AuthError  -> handleAuth(e)
        // new sealed XxxError without a branch here = compile error
    }

    private fun handleOrder(e: OrderError) = when (e) {
        is OrderError.NotFound         -> status(404).body(ErrorEnvelope("order.not_found", e.message!!))
        is OrderError.AlreadyConfirmed -> status(409).body(ErrorEnvelope("order.already_confirmed", e.message!!))
        is OrderError.EmptyOrder       -> status(422).body(ErrorEnvelope("order.empty", e.message!!))
    }

    private fun handleAuth(e: AuthError) = when (e) {
        is AuthError.EmailAlreadyExists -> status(409).body(ErrorEnvelope("auth.email_taken", e.message!!))
        is AuthError.InvalidCredentials -> status(401).body(ErrorEnvelope("auth.invalid_credentials", e.message!!))
    }

    // Library exception → translated in advice, not in service wrap
    @ExceptionHandler(DataAccessException::class)
    fun handleDb(e: DataAccessException): ResponseEntity<ErrorEnvelope> =
        status(500).body(ErrorEnvelope("infrastructure.db_failure", "database error"))
}
```

## Cross-cutting concerns — declarative via AOP

Anything that applies to "many methods regardless of business meaning" is declarative, not sprinkled in service bodies.

| Concern | Mechanism | Where |
|---|---|---|
| Error envelope | `@RestControllerAdvice` | `api/` (one per app) |
| MDC enrichment (request id, user id, tenant) | `OncePerRequestFilter` + `MDC.put` / `MDC.clear` in `finally` | `api/` filter |
| Audit log of state-changing use cases | `@Audited` annotation + `@Aspect @Around` | `infrastructure/audit/` |
| Latency / counters | Micrometer `@Timed` / `@Counted`, or aspect on a marker annotation | `infrastructure/observability/` |
| Distributed tracing | Micrometer Tracing auto-config | auto-config |
| Coarse authorization | `@PreAuthorize` / `@PostAuthorize` on `@Service` | `application/` |
| Resource authorization | Domain method on the aggregate (`order.assertOwnedBy(actor)`) | `domain/` |
| Transactions | `@Transactional` | `application/` |
| Retry / circuit breaker for outbound calls | Resilience4j (`@Retry`, `@CircuitBreaker`) | `infrastructure/` |

1. **Service body must not touch `MDC`.** Filter/interceptor sets it at the request edge; `finally` clears.
2. **No manual audit `log.info(...)` inside service bodies.** Use `@Audited("order.confirm")` + an `@Aspect`. Operational `info` (milestones) is fine.
3. **No try-catch-then-Micrometer-increment.** Use `@Counted(value = "...", recordFailuresOnly = true)` or wrap in an aspect.
4. **No `SecurityContextHolder.getContext().authentication` inside business logic.** Read actor at the application boundary and pass `Actor` as a typed parameter (or onto the Command).
5. **AOP advice contains no business rules.** Authorization aspect = "is this caller allowed at all"; business rule = "is this state transition legal" (belongs on the entity).

```kotlin
// infrastructure/audit/Audited.kt — annotation only (@Aspect @Around impl elided).
@Target(AnnotationTarget.FUNCTION) @Retention(AnnotationRetention.RUNTIME)
annotation class Audited(val action: String)

// application/OrderService.kt — declarative usage.
@Service class OrderService(/* ... */) {
    @Audited("order.confirm") @Transactional fun confirm(id: OrderId) { /* ... */ }
}
```

## Kotlin idioms

### Warning suppression — forbidden

`@Suppress(...)` is forbidden across all code. No exceptions, no justification comments. Fix the warning's root cause by redesigning the code.

### Nullability

- Public APIs avoid `?`-typed parameters and return values. Use overloads or default values.
- Internal `?` is fine when "absent" is genuinely a domain state. `lateinit` only for DI fields where constructor injection is impossible.
- `!!` is forbidden in production. To assert non-null: `requireNotNull(x) { "<context>" }`.
- `?.let { }` for optional side effects; nesting > 2 deep is BLOCKING (extract a helper).
- `Optional<T>` is forbidden in Kotlin code — use nullable.

### Data classes vs classes vs `value class`

- DTOs, Requests/Responses, Commands/Queries, domain values without behavior → `data class`.
- Domain entity with invariants → `class` with private constructor + factory or `init`.
- Single-property wrapper for type meaning (`UserId`, `Email`) → `@JvmInline value class`.

### Immutability

- `val` over `var` always. `var` only inside narrow function-local scope or where JPA forces it.
- `List<T>` (read-only) for parameters and return types. `MutableList<T>` only inside a function body.
- Collections returned from public APIs are read-only views.

### Functions

- Top-level functions for stateless operations. Don't create a class just to hold static helpers.
- Extension functions for adding domain verbs to existing types — sparingly; prefer regular functions when the receiver is yours.
- `inline fun` for higher-order functions on hot paths only. Profile before inlining.

### Coroutines

- Suspending functions for I/O and async coordination. Spring 6 / Boot 4 supports coroutines on controllers.
- Structured concurrency — every coroutine inside `coroutineScope { }` or a Spring-provided scope. No `GlobalScope`.
- `Dispatchers.IO` for blocking JDBC / file I/O; `Dispatchers.Default` for CPU-bound; never `Dispatchers.Main` server-side.
- `runBlocking` only in `main` and tests.
- **`@Transactional` does not propagate across coroutine context switches.** Spring's tx state is thread-local; `withContext(Dispatchers.IO)` switches threads and loses it. Suspending controllers → `@Transactional` on the suspending service method (coroutine-aware tx manager keeps it attached). `withContext(Dispatchers.IO)` for blocking JDBC → keep the entire DB conversation **inside one transactional boundary**; crossing the boundary across the dispatcher switch is BLOCKING.

## Spring Boot conventions

### Dependency injection

- Constructor injection always. No `@Autowired` on fields.
- Most specific stereotype: `@Service`, `@Repository`, `@RestController`, `@Configuration`. `@Component` only if none fits.
- `@ConfigurationProperties` data class, validated with `@Validated`. Prefer over `@Value`.

### Configuration

- `application.yml` (not `.properties`). Profiles for environments (`application-dev.yml`, etc.).
- Secrets via env var or vault — `${VAR_NAME}` placeholders. Never in YAML.

### Web layer

- `@RestController` for JSON. `@Controller` for server-rendered pages (rare).
- **Controller Bar (enforceable)** — Controllers stay **thin**. Body of any `@RestController` method does **exactly 5 things, in order**:
  1. Receive HTTP-level inputs (`@RequestBody`/`@RequestParam`/`@RequestHeader`/`HttpServletRequest`).
  2. Pack them into a single `Command`/`Query` via a trivial `from(...)` factory (no branching beyond nullable defaults).
  3. Call **one** application-service method.
  4. Map the returned `View`/`Result` to a `Response` via a trivial `toResponse()` mapper.
  5. Return `ResponseEntity` (or throw — `@RestControllerAdvice` handles it).

  **FORBIDDEN inside any `@RestController` class** (each occurrence = Roastmaster BLOCKING):
  - `when`/`if`/`?:` **business branches** (kind dispatch, componentId routing, status-based dispatch). Nullable-default fallbacks (`headerRequestId ?: MDC.get("requestId")`) are the only exception.
  - `JsonNode` / `Map<String, Any>` / raw `String` parsing helpers (`extract*`, `parse*`, `dispatchTo*`). All payload shaping lives in `application/` parsers.
  - Auth / token / signature verification — must be a `Filter`, `HandlerInterceptor`, or `@PreAuthorize`. Controller does not read query-string `token`.
  - Cross-cutting concerns: `requestId`/UUID generation, MDC mutation, audit-log persistence, progress logging (`logger.info("step N …")` × N). Single entry/exit log only via interceptor/AOP.
  - **Private helper methods** in the controller class, except a `companion object` Request/Response factory when absolutely necessary. Move helpers to `application/` parsers/mappers.
  - Direct repository / JPA / `ObjectMapper` access.
  - More than **one** collaborator injected per controller method's call path — route to a single application boundary (Facade or service method), don't orchestrate 3–5 collaborators.

  Numeric guideline (Roastmaster threshold): controller method body ≤ **8 lines** excluding blank lines and the signature. Controller class total ≤ **40 lines** for a single endpoint pair. Beyond either → extract to application Facade.
- Validation: `@Valid` + `jakarta.validation` on Request.
- Error envelope: one `@RestControllerAdvice`, uniform shape `{ error: { code, message, details } }`. No raw stack traces to clients.

### Logging

- SLF4J via Kotlin Logging (`KotlinLogging.logger {}`). Structured (key-value in MDC); MDC populated by the request filter, never by service code.
- Levels: `error` (actionable), `warn` (degraded but handled), `info` (milestones — startup, shutdown, boundary), `debug` (verbose; off in prod).
- Never log secrets, unbounded request bodies, or stack traces of expected business exceptions.

### Transactions

- `@Transactional` on `@Service`. Not on controller. Not on repository.
- Default propagation `REQUIRED`. Isolation = `Isolation.DEFAULT` — delegates to DB (Postgres → READ_COMMITTED, MySQL InnoDB → REPEATABLE_READ); set explicitly when the use case demands a specific level. Read paths: `@Transactional(readOnly = true)`.
- Single transaction per use case. Cross-aggregate orchestration → saga / outbox / eventual consistency; never stretch a tx across remote calls. See `data-access`.

## Project structure

```
src/main/kotlin/<root-package>/
├── <bounded-context>/
│   ├── api/              # @RestController, Request/Response, advice
│   ├── application/      # @Service, Command/Query/View, repository INTERFACES, mappers
│   ├── domain/           # entities, value objects, domain services, sealed errors
│   └── infrastructure/   # @Repository impls, HTTP clients, JPA @Entity, aspects, filters
├── common/               # cross-context utilities, error envelope, base config
└── Application.kt        # @SpringBootApplication entry point
```

One bounded context per package directly under root. Cross-context calls go through the other context's `application/`.

## Build and tooling

- Gradle Kotlin DSL (`build.gradle.kts`), not Groovy. Toolchain pinned in `build.gradle.kts`; JVM target = deployed JDK (no drift).
- Spring Boot BOM for transitive versions.
- ktlint or detekt configured; pre-commit hook runs both. Format errors fail CI.

### Canonical commands (rescue trigger matches on these)

- `./gradlew build` — compile + test + checks.
- `./gradlew test` — tests only.
- `./gradlew test --tests "<FQCN>"` — single class.
- `./gradlew test --tests "<FQCN>.<method>"` — single method.
- `./gradlew ktlintCheck` (or detekt equivalent) — lint only.

The `error_signature` in `adversarial-review-bridge` matches on these strings — do not deviate without updating the bridge skill.

## Performance smells (Roastmaster blocks on)

- N+1 queries in JPA (see `data-access`).
- `@Transactional` on a controller method.
- Blocking JDBC inside a coroutine without `Dispatchers.IO`.
- Mutable list returned from a public service method.
- `runBlocking` outside main/tests.
- Reflection-based serialization in hot paths.

## When this skill conflicts with the AC

If an AC explicitly demands a deviation, document it in the Design Doc and notify Roastmaster in advance. AC waivers are in-scope for stack overlays.
