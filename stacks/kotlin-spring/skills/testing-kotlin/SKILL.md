---
name: testing-kotlin
description: Test framework and patterns for Kotlin + Spring Boot — JUnit 5, Kotest, MockK, Testcontainers, Spring Boot Test slices. Use whenever tests are written or reviewed in this stack. Stack-specific overlay on testing-principles.
---

# Testing — Kotlin + Spring Boot

Stack-specific overlay on `testing-principles`. When this skill and `testing-principles` agree, follow `testing-principles`. When they diverge, this skill wins for Kotlin/Spring tests.

## Frameworks (pinned choices)

| Layer | Tool | Why |
|---|---|---|
| Test runner | **JUnit 5** (Jupiter) | Spring's first-class support, parametrized tests, lifecycle hooks |
| Assertion / DSL | **Kotest** (assertion module only) | richer than JUnit assertions; Kotest Spec runner is **not** used (we stay on Jupiter) |
| Mocking | **MockK** | Kotlin-native; handles final classes, coroutines, extension functions |
| Real DB | **Testcontainers** (Postgres, MySQL — match prod) | catches schema drift, dialect issues; required for repository tests |
| HTTP mocking | **WireMock** | for outbound HTTP clients |
| Property-based | **Kotest property** (where it earns its keep) | invariants and round-trip tests |

Mockito is forbidden in new code; existing Mockito tests are migrated when touched.

## Test types and Spring Boot test slices

| Type | Annotation | Speed | Use for |
|---|---|---|---|
| Plain unit | none | < 100 ms | pure logic, services with mocked deps |
| `@WebMvcTest` | yes | < 500 ms | controllers + validation, no full context |
| `@DataJpaTest` | yes (with Testcontainers) | < 1 s | repositories, query correctness, schema |
| `@SpringBootTest` | yes (sparingly) | seconds | end-to-end wire-up sanity, full-context integration |
| Acceptance / E2E | `@SpringBootTest(webEnvironment = RANDOM_PORT)` | seconds | What-If Witch's AC tests for `/feat` |

Default for service-layer tests: **plain unit + MockK**. Reach for `@SpringBootTest` only when the test genuinely needs real Spring wiring.

## File structure

```
src/test/kotlin/<root-package>/
├── <bounded-context>/
│   ├── api/<Controller>WebMvcTest.kt
│   ├── application/<Service>Test.kt
│   └── infrastructure/<Repository>Test.kt        # @DataJpaTest + Testcontainers
└── support/
    ├── fixtures/                                   # test data builders
    └── TestcontainersConfig.kt
```

Test class name mirrors production class + `Test` suffix. Acceptance tests live under `src/test/kotlin/<context>/acceptance/<feature>AcceptanceTest.kt`.

## JUnit 5 patterns

### Naming

```kotlin
@Test
fun `should return 404 when user not found`() { … }

@Test
@DisplayName("AC-001: should reject email shorter than 3 characters")
fun ac001_email_too_short() { … }
```

Backtick-quoted method names for prose. `@DisplayName` for AC traceability — every acceptance test must include the `AC-NNN` ID in `@DisplayName`.

### Lifecycle

`@BeforeEach` for per-test setup; never `@BeforeAll` for mutable state. `@AfterEach` for cleanup — DB cleanup is handled by `@DataJpaTest` rollback or Testcontainers isolation.

### Parametrized

```kotlin
@ParameterizedTest
@CsvSource("a, 1", "b, 2")
fun `should map letter to number`(input: String, expected: Int) { … }
```

Use `@MethodSource` when the data needs structured types.

## Kotest assertions

```kotlin
result shouldBe expected
result.size shouldBeGreaterThan 0
result shouldHaveSize 3
exception shouldBeInstanceOf <ValidationException>
```

Prefer infix `shouldBe`/`shouldNotBe`/`shouldHaveSize` over `assertEquals` — reads better, fails better.

## MockK patterns

### Basic mock

```kotlin
val repo = mockk<UserRepository>()
every { repo.findById(1L) } returns user
val service = UserService(repo)

service.get(1L) shouldBe user

verify(exactly = 1) { repo.findById(1L) }
```

### Coroutines

```kotlin
coEvery { client.fetch(any()) } returns response
runTest {
    service.process()
    coVerify { client.fetch(any()) }
}
```

### Spy / relaxed

`relaxed = true` only when unmocked methods would clutter the test (prefer explicit `every`). `spyk` only for legacy code that cannot accept an injected mock.

## Spring Boot test slices

### `@WebMvcTest`

```kotlin
@WebMvcTest(UserController::class)
class UserControllerTest {
    @MockkBean lateinit var service: UserService
    @Autowired lateinit var mvc: MockMvc

    @Test
    fun `should return 400 on invalid email`() {
        mvc.post("/users") {
            contentType = APPLICATION_JSON
            content = """{"email":"x"}"""
        }.andExpect { status { isBadRequest() } }
    }
}
```

Use `@MockkBean` (from `springmockk`) — not `@MockBean`. Mockito-based `@MockBean` is forbidden.

### `@DataJpaTest` with Testcontainers

```kotlin
@DataJpaTest
@Testcontainers
@AutoConfigureTestDatabase(replace = NONE)
class UserRepositoryTest {
    companion object {
        @Container
        @ServiceConnection
        val pg = PostgreSQLContainer("postgres:16-alpine")
    }

    @Autowired lateinit var repo: UserRepository

    @Test
    fun `should find by email case-insensitively`() {
        repo.save(User(email = "Alice@Example.com"))
        repo.findByEmail("alice@example.com") shouldNotBe null
    }
}
```

`@ServiceConnection` (Spring Boot 3.1+) wires the container's URL automatically. No manual property overrides.

**Mandatory**: every `@Repository` change is tested with `@DataJpaTest` + Testcontainers. Mock-only tests for repositories are BLOCKING per `testing-principles`.

## Test data builders

Avoid 10-arg constructors. Build helpers per aggregate in `support/fixtures/`:

```kotlin
fun aUser(
    id: Long = 1L,
    email: String = "test@example.com",
    status: UserStatus = ACTIVE,
): User = User(id = id, email = email, status = status)
```

## Canonical commands

Rescue trigger matches on these strings:

- `./gradlew test` — full suite (superset: every slice + ArchUnit + JaCoCo + contract)
- `./gradlew test --tests "<FQCN>"` — single class
- `./gradlew test --tests "<FQCN>.<method>"` — single method
- `./gradlew compileKotlin` — compile-only fast check
- `./gradlew build` — build verification (compile + test + assemble)

Iteration: `compileKotlin` + scoped `--tests`. Pre-push: `./gradlew test` once. No cascade — the full suite covers every subset.

## Coverage and CI

- JaCoCo configured; reports in CI artifacts.
- Coverage gate: 80% line coverage on changed files; falling below blocks the PR.
- Coverage is a guide — don't write throwaway tests to lift the number.

## Common smells (Roastmaster blocks on)

- Test asserting `expected = mockReturn` (no actual transformation verified).
- `@SpringBootTest` used where `@WebMvcTest` or plain unit would suffice.
- `Thread.sleep` in tests (use `Awaitility` for async waits, fixed clocks for time).
- Tests that share mutable static state (`object`, `companion object` mutated across tests).
- Repository test using H2 instead of Testcontainers when prod uses Postgres/MySQL (dialect drift).
- Skipping (`@Disabled`) without a linked ticket.
- Real network calls (no WireMock, no Testcontainers — actual outbound HTTP).
- `runBlocking` instead of `runTest` for coroutine tests (loses virtual time, slower).

## When this skill conflicts with the AC

If an AC explicitly demands a slower test type (e.g., `@SpringBootTest` for an inherently full-stack acceptance check), follow the AC. Document in the Design Doc's verification strategy.
