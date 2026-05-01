# Kotlin 2.3 feature guide for agents

Target: Kotlin 2.3.0, 2.3.20, and 2.3.21 (bugfix; adds no capsules). For
stability/mode, use [status-index.md](./status-index.md) (sole source of
truth). Shared rules (verified date, stability/modes model, lookup
priority, freshness) live in [../SKILL.md](../SKILL.md). This file holds
capsule bodies — usage, enablement, notes, sources — and stub pointers
for features canonical in another guide.

## Feature capsules

### id: kt23-nested-type-aliases

Area: Language

Use when:

- A type alias is meaningful only inside a class, interface, object, or another
  type, and keeping it local improves API organization.

Usage:

```kotlin
class Parser {
    typealias TokenMap = Map<String, List<Token>>

    data class Token(val value: String)

    fun parse(tokens: TokenMap) {
        // ...
    }
}
```

Notes for agents:

- Nested aliases improve namespacing; they do not create new runtime types.
- Avoid aliases that hide important type complexity from API users.
- If compiling with 2.2.x, the feature flag is required. With 2.3.0+, it is
  stable.

Sources:

- https://kotlinlang.org/docs/whatsnew22.html
- https://kotlinlang.org/docs/whatsnew23.html

### id: kt23-data-flow-exhaustiveness

Area: Language

Note: in 2.2.20 this is gated by the `-Xdata-flow-based-exhaustiveness`
compiler flag, **not** by `-language-version 2.3` (the language-version
preview path is used by `kt23-expression-body-return`, not by this feature).

Use when:

- A `when` over a sealed type, enum, Boolean, nullable type, or similar domain
  can be proven exhaustive after prior control flow narrows possible values.

Usage:

```kotlin
sealed interface Response
data object Loading : Response
data object Success : Response
data object Failure : Response

fun render(response: Response): String {
    if (response is Loading) return "loading"

    return when (response) {
        Success -> "ok"
        Failure -> "failed"
    }
}
```

Notes for agents:

- This can remove unnecessary `else` branches after a value has been narrowed.
- Do not delete `else` branches that are intentionally defensive for binary
  compatibility against future subclasses.

Sources:

- https://kotlinlang.org/docs/whatsnew2220.html
- https://kotlinlang.org/docs/whatsnew23.html

### id: kt23-expression-body-return

Area: Language

Use when:

- A function with an expression body needs an early `return` inside a nested
  expression, commonly in Elvis expressions or inline lambdas.

Usage:

```kotlin
fun normalize(input: String?): String =
    input?.trim()?.takeIf { it.isNotEmpty() } ?: return "default"
```

Notes for agents:

- This reduces the need to convert short expression-bodied functions to block
  bodies.
- Use sparingly. If there are several early returns, a block body is clearer.

Sources:

- https://kotlinlang.org/docs/whatsnew2220.html
- https://kotlinlang.org/docs/whatsnew23.html

### id: kt23-reified-catch

Area: Language

Use when:

- An inline generic helper catches an exception type provided as a reified type
  parameter.

Usage:

```kotlin
inline fun <reified E : Throwable, T> recover(block: () -> T, fallback: () -> T): T {
    return try {
        block()
    } catch (e: E) {
        fallback()
    }
}
```

Notes for agents:

- Only use in modules that already accept experimental compiler flags.
- Keep exception handling obvious. Generic catch helpers can hide important
  behavior.

Source: https://kotlinlang.org/docs/whatsnew2220.html

### id: kt23-unused-return-value

Area: Language / Diagnostics

Use when:

- Library or application code wants compiler diagnostics when important return
  values are ignored.

Enablement:

```kotlin
compilerOptions {
    freeCompilerArgs.add("-Xreturn-value-checker=check")
    // or "-Xreturn-value-checker=full" for all non-Unit returns
}
```

Usage:

```kotlin
@MustUseReturnValues
class TransactionBuilder {
    fun commit(): CommitResult = CommitResult()
}

@IgnorableReturnValue
fun log(message: String): LogToken = LogToken(message)
```

Notes for agents:

- `check` reports ignored returns only for declarations annotated with
  `@MustUseReturnValues`.
- `full` checks all non-`Unit` return values except declarations marked with
  `@IgnorableReturnValue`.
- To intentionally ignore a value, bind it to `_`:

```kotlin
val _ = builder.commit()
```

Source: https://kotlinlang.org/docs/whatsnew23.html

### id: kt23-name-based-destructuring

Area: Language

Use when:

- Destructuring should bind variables by property name instead of by
  `componentN()` position.
- Code should make positional destructuring explicit with square brackets.

Enablement:

```kotlin
compilerOptions {
    freeCompilerArgs.add("-Xname-based-destructuring=only-syntax")
}
```

Usage:

```kotlin
data class User(val username: String, val email: String)

fun named(user: User) {
    (val mail = email, val name = username) = user
    println(name)
    println(mail)
}

fun positional(user: User) {
    val [username, email] = user
    println(username)
    println(email)
}
```

Notes for agents:

- With `only-syntax`, use the explicit form `(val local = property) = value`.
  Existing short-form `val (a, b) = value` remains position-based.
- `complete` mode makes short-form parentheses name-based and keeps square
  brackets for explicit position-based matching.
- Square brackets are available for explicit position-based matching.
- This is a migration-oriented experimental feature. Do not introduce it into
  codebases that are not already evaluating the new destructuring model.

Source: https://kotlinlang.org/docs/whatsnew2320.html

### id: kt24-explicit-backing-fields

Canonical capsule: [kotlin-2.4-eap-feature-guide.md](./kotlin-2.4-eap-feature-guide.md) → search for `### id: kt24-explicit-backing-fields`.

### id: kt24-annotation-targets

Canonical capsule: [kotlin-2.4-eap-feature-guide.md](./kotlin-2.4-eap-feature-guide.md) → search for `### id: kt24-annotation-targets`.

### id: kt23-context-parameter-overload-resolution

Area: Language

Use when:

- Code has overloads that differ only by context parameters.
- A 2.3.20 upgrade introduces ambiguity around calls inside `context(...)`
  blocks.

Usage:

```kotlin
class Logger {
    fun info(message: String) = println(message)
}

fun save(id: Int) {
    println("save without logger")
}

context(logger: Logger)
fun save(id: Int) {
    logger.info("save with logger")
}
```

Notes for agents:

- Before 2.3.20, overloads with context parameters were treated as more
  specific than overloads without them.
- Starting in 2.3.20, that specificity rule no longer applies. Calls that
  previously resolved can become ambiguous when overloads differ only by
  context parameters.
- Prefer distinct names or an explicit receiver/argument strategy instead of
  relying on context-only overload selection. In 2.4 EAP, explicit context
  arguments can help disambiguate, but they remain experimental.
- Kotlin 2.3.20 also reduces the number of `kotlin.context` overloads from 22
  to 6 to reduce excessive candidates in resolution and code completion.

Source: https://kotlinlang.org/docs/whatsnew2320.html

### id: kt22-context-sensitive-resolution

Canonical capsule: [kotlin-2.2-feature-guide.md](./kotlin-2.2-feature-guide.md) → search for `### id: kt22-context-sensitive-resolution`.

### id: kt22-contracts

Canonical capsule: [kotlin-2.2-feature-guide.md](./kotlin-2.2-feature-guide.md) → search for `### id: kt22-contracts`.

### id: kt23-stdlib-time

Area: Standard library

Use when:

- Common Kotlin code needs wall-clock time or instant parsing/formatting.

Usage:

```kotlin
import kotlin.time.Clock

fun issuedAt(): String =
    Clock.System.now().toString()
```

Notes for agents:

- Prefer `kotlin.time.Clock` and `kotlin.time.Instant` in common code over
  platform-specific time classes.
- Some related APIs, especially UUID time-based generation, can still be
  experimental. Check annotations in the target version.

Source: https://kotlinlang.org/docs/whatsnew23.html

### id: kt23-stdlib-uuid

Area: Standard library

Use when:

- Common code needs UUID parsing, formatting, byte conversion, or generation.

Usage:

```kotlin
import kotlin.uuid.Uuid

fun parseId(raw: String): Uuid =
    Uuid.parse(raw)

fun idBytes(id: Uuid): ByteArray =
    id.toByteArray()
```

Generation:

```kotlin
import kotlin.uuid.ExperimentalUuidApi
import kotlin.uuid.Uuid

@OptIn(ExperimentalUuidApi::class)
fun randomId(): Uuid =
    Uuid.random()
```

Notes for agents:

- In 2.4.0-Beta2, use parsing and formatting as common stable APIs but keep
  generation opt-in until final status is verified.
- For 2.3.x, treat the UUID API as experimental.

Sources:

- https://kotlinlang.org/docs/whatsnew23.html
- https://kotlinlang.org/docs/whatsnew-eap.html

### id: kt23-stdlib-map-entry-copy

Area: Standard library

Use when:

- Transforming map entries while changing only key or value.

Usage:

```kotlin
@OptIn(kotlin.ExperimentalStdlibApi::class)
fun normalize(entries: List<Map.Entry<String, Int>>): List<Map.Entry<String, Int>> =
    entries.map { entry -> entry.copy(key = entry.key.lowercase()) }
```

Notes for agents:

- This is experimental; prefer plain `entry.key to entry.value` in conservative
  code.

Source: https://kotlinlang.org/docs/whatsnew2320.html

### id: kt23-jvm-java-versions

Area: JVM / Toolchain

Use when:

- Updating toolchains or bytecode target in JVM projects.

Notes for agents:

- Compatibility with a JDK does not mean the project should target that
  bytecode level. Check runtime deployment constraints.
- If a project specifically needs Java 26 *annotation processing* (kapt)
  rather than bytecode generation, the skill cannot confirm Kotlin support
  from current sources — verify against the upstream docs before recommending
  any version.

Sources:

- https://kotlinlang.org/docs/whatsnew23.html
- https://kotlinlang.org/docs/whatsnew-eap.html

### id: kt23-jvm-nullability-annotations

Area: JVM / Java interop

Detail (2.3.20):

- Vert.x nullability annotations are now supported.
- `@Unmodifiable`, `@UnmodifiableView`, and `@ReadOnly` from
  `org.jspecify.annotations` and `org.jetbrains.annotations` are handled
  more accurately.

Use when:

- Calling Java APIs from Kotlin and relying on nullability or mutability
  annotations for safer types.

Build:

```kotlin
compilerOptions {
    freeCompilerArgs.add("-Xnullability-annotations=@io.vertx.codegen.annotations:strict")
}
```

Notes for agents:

- Strict mode can surface new warnings or errors in Java interop-heavy code.
- Treat annotation package configuration as a project policy decision.

Source: https://kotlinlang.org/docs/whatsnew2320.html

### id: kt23-jvm-jpa-plugin

Area: JVM / Compiler plugin

Mechanic: the `org.jetbrains.kotlin.plugin.jpa` Gradle plugin now
automatically applies the `org.jetbrains.kotlin.plugin.all-open` plugin
with the JPA preset. JPA-annotated entities are auto-`open` with no-arg
constructors generated, with no extra `all-open` configuration required.
The JPA preset's annotation list (`javax.persistence` and
`jakarta.persistence` annotations) was already supported earlier; the
2.3.20 change is the auto-application.

Use when:

- Kotlin JPA entities need generated no-arg constructors for either legacy
  Javax Persistence or Jakarta Persistence annotations, and you want the
  `all-open` plugin applied automatically.

Usage:

```kotlin
plugins {
    kotlin("plugin.jpa") version "2.3.20"
}
```

Notes for agents:

- Keep plugin version aligned with Kotlin plugin version.
- This is specifically for JPA constructor requirements; do not use as a
  general entity modeling solution.

Source: https://kotlinlang.org/docs/whatsnew2320.html

### id: kt23-jvm-lombok

Area: JVM / Compiler plugin

Use when:

- Kotlin code must interoperate with Java source using Lombok-generated
  members, and the project accepts alpha compiler plugin risk.

Notes for agents:

- Prefer removing Lombok from new Kotlin-facing APIs when possible.
- If used, isolate the dependency and pin Kotlin/Lombok versions carefully.
- Expect limitations; verify generated member visibility with compilation
  tests.

Source: https://kotlinlang.org/docs/whatsnew2320.html

### id: kt22-native-swift-export

Canonical capsule: [kotlin-2.2-feature-guide.md](./kotlin-2.2-feature-guide.md) → search for `### id: kt22-native-swift-export`.

### id: kt23-native-cinterop-beta

Area: Native / C and Objective-C interop

Use when:

- Importing C or Objective-C declarations with the newer cinterop behavior.

Notes for agents:

- Beta means the Kotlin team expects broad use but may still refine details.
- Recompile and test all native targets after cinterop updates.
- 2.3.0 also improved Objective-C headers by generating Kotlin fully qualified
  names in `@ObjCName` annotations by default.

Source: https://kotlinlang.org/docs/whatsnew23.html

### id: kt23-native-cinterop-new-mode

Area: Native / C interop

Use when:

- You want direct use of C declarations from the cinterop artifact without
  importing the full interoperability package surface into public API.

Notes for agents:

- Do not publish libraries built with this new mode unless the project
  explicitly accepts experimental ABI risk.
- Keep cinterop wrappers narrow and test across targets.

Source: https://kotlinlang.org/docs/whatsnew2320.html

### id: kt23-native-cache-dsl

Area: Native / Gradle

No source-side action — see `status-index.md` for status. Build-infra
work; keep out of library source patches unless requested.

Source: https://kotlinlang.org/docs/whatsnew2320.html

### id: kt23-wasm-fqn

Area: Wasm / Diagnostics

No source-side action — see `status-index.md` for status. May affect
tests that compare class-name strings.

Source: https://kotlinlang.org/docs/whatsnew23.html

### id: kt23-wasm-exception-handling

Area: Wasm / Runtime

No source-side action — see `status-index.md` for status. Default for
`wasmWasi` only; `wasmJs` behavior may differ.

Source: https://kotlinlang.org/docs/whatsnew23.html

### id: kt23-wasm-performance

Area: Wasm / Runtime and compiler

Detail:

- 2.3.0: compact Latin-1 string support, heap-memory reduction, initial
  binary-size and string-performance improvements.
- 2.3.20: ~5% smaller Wasm binaries, up to 4.6× faster string interpolation,
  ≥20% faster `StringBuilder.append()` and concatenation, ~1% median
  benchmark improvement, ~65% faster clean builds and ~21% faster
  incremental builds in the Kotlin Gradle plugin.

Use when:

- Explaining or validating performance changes after upgrading Wasm projects.

Notes for agents:

- Mostly source-compatible improvements.
- Benchmark real workloads because string-heavy and allocation-heavy apps may
  benefit differently.

Sources:

- https://kotlinlang.org/docs/whatsnew23.html
- https://kotlinlang.org/docs/whatsnew2320.html

### id: kt23-wasm-native-invoke

Area: Wasm / JS interop

Use when:

- A Kotlin/Wasm external declaration should behave like a callable JS function
  object.

Usage shape:

```kotlin
import kotlin.js.ExperimentalWasmJsInterop
import kotlin.js.nativeInvoke

external class JsAction {
    @OptIn(ExperimentalWasmJsInterop::class)
    @nativeInvoke
    operator fun invoke(value: String)
}

fun runAction(action: JsAction) {
    action("Run")
}
```

Notes for agents:

- Verify exact annotation import and supported declaration forms in the target
  Kotlin version.
- Use only for Wasm interop layers, not ordinary application code.

Source: https://kotlinlang.org/docs/whatsnew2320.html

### id: kt23-js-suspend-export

Area: JavaScript / Export interop

Use when:

- Kotlin/JS APIs marked with `@JsExport` need to expose suspend functions to
  JavaScript or TypeScript without manual wrappers.

Enablement:

```kotlin
compilerOptions {
    freeCompilerArgs.add("-Xenable-suspend-function-exporting")
}
```

Usage:

```kotlin
@JsExport
class UserApi {
    suspend fun loadUser(id: String): String = id
}
```

Notes for agents:

- This is experimental in 2.3.x. Do not add it to published JS APIs unless the
  project accepts experimental compiler behavior.
- Regenerate TypeScript declarations and run JS/TS consumer checks after
  enabling it.

Source: https://kotlinlang.org/docs/whatsnew23.html

### id: kt23-js-longarray-bigint

Area: JavaScript / Export interop

Use when:

- Kotlin/JS should represent `LongArray` values as JavaScript `BigInt64Array`
  instead of `Array<bigint>`, especially for typed-array interop.

Enablement:

```kotlin
kotlin {
    js {
        compilerOptions {
            freeCompilerArgs.add("-Xes-long-as-bigint")
        }
    }
}
```

Notes for agents:

- Requires JavaScript runtimes and consumers that support `BigInt64Array`.
- This uses the same compiler flag as the 2.2.20 `Long` as `BigInt` feature,
  but the 2.3.0 behavior specifically covers `LongArray` representation.
- Check generated TypeScript declarations and binary compatibility with
  existing JS consumers.

Sources:

- https://kotlinlang.org/docs/whatsnew23.html
- https://kotlinlang.org/docs/whatsnew2220.html

### id: kt23-js-export-defaults

Area: JavaScript / Export interop

2.3.0 `@JsExport`-related improvements:

- unified companion object access across JS module systems,
- `@JsStatic` supported in interfaces with companion objects,
- `@JsQualifier` allowed on individual functions and classes,
- JavaScript default exports via `@JsExport.Default` (generates
  `export default ...` for ES modules).

Two related 2.3.0 JS-export features have their own capsules:
suspend-function export (`kt23-js-suspend-export`) and `LongArray` as
`BigInt64Array` (`kt23-js-longarray-bigint`). "Functions with default
parameters" is **not** a 2.3.0 export feature — Kotlin's existing
default-parameter handling is unchanged.

Use when:

- Designing Kotlin/JS APIs consumed from JavaScript or TypeScript.

Notes for agents:

- Re-generate and inspect TypeScript declarations after exporting APIs.
- `@JsExport.Default` only affects the generated ES-module `export default`
  statement; it does not change the declaration's API.

Source: https://kotlinlang.org/docs/whatsnew23.html

### id: kt23-js-typescript-declarations

Area: JavaScript / TypeScript interop

Use when:

- TypeScript code should implement interfaces exported from Kotlin with
  `@JsExport`.

Notes for agents:

- This affects generated `.d.ts` surfaces and how JS consumers implement
  Kotlin-defined interfaces. Treat it as a public API change.
- Add TypeScript compile checks if publishing JS packages.

Source: https://kotlinlang.org/docs/whatsnew2320.html

### id: kt23-js-swc

Area: JavaScript / Build tooling

Use when:

- Kotlin/JS builds want to use SWC for minification.

Notes for agents:

- Compare output size and runtime behavior with the existing minifier.
- Keep source maps and diagnostics in mind.

Source: https://kotlinlang.org/docs/whatsnew2320.html

### id: kt23-gradle-generated-sources-api

Area: Gradle / Source generation

Use when:

- A Gradle plugin or build script should register generated Kotlin sources with
  the Kotlin Gradle plugin in a supported way.

Notes for agents:

- Prefer the generated sources API over ad hoc source set mutation when the
  project is already on Kotlin 2.3+ and accepts experimental API use.
- Keep generator task dependencies explicit.

Source: https://kotlinlang.org/docs/whatsnew23.html

### id: kt23-gradle-bta-default

Area: Gradle / Build tools API

Scope: in 2.3.20, only **Kotlin/JVM compilation** in the Kotlin Gradle
plugin uses the Build tools API (BTA) by default. Other compilation paths
are not stated to default to BTA on the source page.

Use when:

- Explaining behavior changes, diagnostics, or metrics in Gradle builds after
  upgrading to 2.3.20.

Notes for agents:

- Most projects should not need source changes.
- If custom Gradle integrations break, check whether they relied on older
  internal compiler invocation behavior.

Source: https://kotlinlang.org/docs/whatsnew2320.html

### id: kt23-maven-simplified-setup

Area: Maven

Use when:

- Simplifying Kotlin Maven plugin setup with extension-based configuration.

Usage:

```xml
<plugin>
  <groupId>org.jetbrains.kotlin</groupId>
  <artifactId>kotlin-maven-plugin</artifactId>
  <version>2.3.20</version>
  <extensions>true</extensions>
</plugin>
```

Notes for agents:

- Keep Maven lifecycle and Java/Kotlin compile ordering in mind.
- If the project already has custom executions, migrate carefully.

Source: https://kotlinlang.org/docs/whatsnew2320.html

### id: kt22-compose-compiler

Canonical capsule: [kotlin-2.2-feature-guide.md](./kotlin-2.2-feature-guide.md) → search for `### id: kt22-compose-compiler`.
