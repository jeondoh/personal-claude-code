---
name: testing-kotlin
description: Test framework and patterns for Kotlin + Spring Boot — JUnit 5, Kotest, MockK, Testcontainers, Spring Boot Test slices. Use whenever tests are written or reviewed in this stack. Stack-specific overlay on testing-principles.
---

# Testing — Kotlin + Spring Boot

Overlay on `testing-principles`; on divergence this skill wins for Kotlin/Spring tests.

## Frameworks (pinned)

| Layer | Tool | Notes |
|---|---|---|
| Runner | **JUnit 5** (Jupiter) | Kotest Spec runner **not** used — stay on Jupiter |
| Assertion | **Kotest** (assertion module only) | richer + better failures than JUnit |
| Mocking | **MockK** | Kotlin-native: final classes, coroutines, ext functions |
| Real DB | **Testcontainers** (Postgres/MySQL — match prod) | required for repo tests; catches schema/dialect drift |
| HTTP mocking | **WireMock** | outbound clients |
| Property-based | **Kotest property** | invariants, round-trip |

Mockito forbidden in new code; migrate existing Mockito tests when touched.

## Test types / Spring Boot slices

| Type | Annotation | Speed | Use for |
|---|---|---|---|
| Plain unit | none | < 100 ms | pure logic, services with mocked deps |
| `@WebMvcTest` | yes | < 500 ms | controllers + validation, no full context |
| `@DataJpaTest` | yes + Testcontainers | < 1 s | repositories, query correctness, schema |
| `@SpringBootTest` | yes (sparingly) | seconds | full-context integration, wire-up sanity |
| Acceptance / E2E | `@SpringBootTest(webEnvironment = RANDOM_PORT)` | seconds | What-If Witch's AC tests for `/feat` |

Service-layer default: **plain unit + MockK**. Reach for `@SpringBootTest` only when real Spring wiring is genuinely needed.

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

Test class = production class + `Test`. Acceptance: `src/test/kotlin/<context>/acceptance/<feature>AcceptanceTest.kt`.

## JUnit 5

Backtick-quoted method names for prose. Every acceptance test MUST include the `AC-NNN` ID in `@DisplayName`.

```kotlin
@Test
fun `should return 404 when user not found`() { … }

@Test
@DisplayName("AC-001: should reject email shorter than 3 characters")
fun ac001_email_too_short() { … }
```

- Lifecycle: `@BeforeEach` per-test setup; never `@BeforeAll` for mutable state. `@AfterEach` for cleanup — DB cleanup via `@DataJpaTest` rollback or Testcontainers isolation.
- Parametrized: `@ParameterizedTest` + `@CsvSource`; `@MethodSource` when data needs structured types.

```kotlin
@ParameterizedTest
@CsvSource("a, 1", "b, 2")
fun `should map letter to number`(input: String, expected: Int) { … }
```

## Kotest assertions

Prefer infix `shouldBe`/`shouldNotBe`/`shouldHaveSize` over `assertEquals` — reads and fails better.

```kotlin
result shouldBe expected
result.size shouldBeGreaterThan 0
result shouldHaveSize 3
exception shouldBeInstanceOf <ValidationException>
```

## MockK

```kotlin
val repo = mockk<UserRepository>()
every { repo.findById(1L) } returns user
UserService(repo).get(1L) shouldBe user
verify(exactly = 1) { repo.findById(1L) }

// coroutines
coEvery { client.fetch(any()) } returns response
runTest {
    service.process()
    coVerify { client.fetch(any()) }
}
```

`relaxed = true` only when unmocked methods clutter (prefer explicit `every`). `spyk` only for legacy code that can't accept an injected mock.

## Spring Boot test slices

### `@WebMvcTest`

Use `@MockkBean` (from `springmockk`) — Mockito-based `@MockBean` is forbidden.

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

### `@DataJpaTest` + Testcontainers

`@ServiceConnection` (Spring Boot 3.1+) wires the container URL automatically — no manual property overrides.

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

**Mandatory**: every `@Repository` change is tested with `@DataJpaTest` + Testcontainers. Mock-only repository tests are BLOCKING per `testing-principles`.

## Test data builders

Avoid 10-arg constructors — build helpers per aggregate in `support/fixtures/`:

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

Iteration: `compileKotlin` + scoped `--tests`. Pre-push: `./gradlew test` once. No cascade — full suite covers every subset.

## Coverage and CI

- JaCoCo configured; reports in CI artifacts.
- Gate: 80% line coverage on changed files; below blocks the PR.
- Coverage is a guide — don't write throwaway tests to lift the number.

## Common smells (Roastmaster blocks on)

- Asserting `expected = mockReturn` (no actual transformation verified).
- `@SpringBootTest` where `@WebMvcTest` or plain unit would suffice.
- `Thread.sleep` (use `Awaitility` for async, fixed clocks for time).
- Shared mutable static state (`object` / `companion object` mutated across tests).
- Repository test using H2 instead of Testcontainers when prod uses Postgres/MySQL (dialect drift).
- `@Disabled` without a linked ticket.
- Real network calls (no WireMock/Testcontainers — actual outbound HTTP).
- `runBlocking` instead of `runTest` for coroutine tests (loses virtual time).

## When this skill conflicts with the AC

If an AC demands a slower test type (e.g., `@SpringBootTest` for an inherently full-stack acceptance check), follow the AC. Document in the Design Doc's verification strategy.
