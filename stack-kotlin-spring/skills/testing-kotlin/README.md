# testing-kotlin

Kotlin + Spring Boot 테스트 코드의 프레임워크 선택과 패턴 (JUnit 5·Kotest·MockK·Testcontainers·Spring Test slices).

## 무엇을 하나

이 스킬은 stack-agnostic `testing-principles` 위에 얹히는 Kotlin/Spring 테스트 오버레이다.
러너는 JUnit 5 Jupiter, assertion 은 Kotest infix DSL, mocking 은 MockK (Mockito 금지),
repository 검증은 Testcontainers 실제 DB (H2 금지) 로 핀한다.

test slice 별 속도 목표·`@MockkBean` 사용·`AC-NNN` `@DisplayName` traceability·canonical Gradle 명령어를 한 곳에 모은다.
Paladin (unit) 과 What-If Witch (acceptance/E2E) 양쪽이 모두 본다.

## 언제 작동하나

이 스택에서 테스트를 작성하거나 리뷰할 때 활성화된다.
`testing-principles` 의 일반 룰 (피라미드·실제-의존성 선호·flake 금지) 을 먼저 적용하고 그 위에 Kotlin/Spring 전용 framework 컨벤션을 얹는다.

## 다루는 주제

- 프레임워크 핀 (JUnit 5 / Kotest assertion / MockK / Testcontainers / WireMock / Kotest property)
- Spring Boot test slices (`@WebMvcTest`·`@DataJpaTest`·`@SpringBootTest`) 와 속도 목표 (100ms / 500ms / 1s / 수 초)
- File structure (production class mirror + `support/fixtures/` + `acceptance/<feature>AcceptanceTest.kt`)
- JUnit 5 네이밍 (backtick prose) · lifecycle · `@ParameterizedTest` 패턴
- Kotest infix assertion (`shouldBe`·`shouldHaveSize`) · MockK basic / coroutine / spy 사용법
- `@DataJpaTest` + Testcontainers + `@ServiceConnection` (real-DB 강제, mock-only repository 테스트는 BLOCKING)
- Test data builders (`aUser(...)`) 와 canonical Gradle 명령어
- Coverage 게이트 (JaCoCo 80% on changed files) 와 Roastmaster 가 블록하는 smell

## 정본 (Source of Truth)

설치된 JUnit / Kotest / MockK / Testcontainers / Spring Boot 버전은 `build.gradle.kts` 가 정본이다.
Spring Boot 메이저 점프 시 test slice 어노테이션 동작 (예: `@ServiceConnection` 추가, `@MockBean` deprecation, `springmockk` 의 `@MockkBean` 권장) 이 바뀔 수 있으므로
training cutoff 보다 새로운 버전에서는 공식 docs 를 확인한 뒤 쓴다.

real-DB 컨테이너 이미지 (예: `postgres:16-alpine`) 는 production 의 DB 메이저와 정확히 맞춘다 — H2 로 대체하면 dialect drift 가 잡히지 않아 BLOCKING.

## 같이 보는 스킬

- [`SKILL.md`](SKILL.md) — Claude 가 실제로 읽는 본문
- [`../../../workflows/skills/testing-principles/SKILL.md`](../../../workflows/skills/testing-principles/SKILL.md) — 상위 stack-agnostic 테스트 원칙
- [`../kotlin-spring-boot-core/SKILL.md`](../kotlin-spring-boot-core/SKILL.md) — production 측 컨벤션 (테스트는 이 layer 구조를 따라간다)
- [`../data-access/SKILL.md`](../data-access/SKILL.md) — repository 테스트 시 real-DB 강제의 근거
