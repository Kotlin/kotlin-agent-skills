# Kotlin 2.2 feature guide for agents

Target: Kotlin 2.2.0 and 2.2.20. For stability/mode, use
[status-index.md](./status-index.md) (sole source of truth). Shared rules
(verified date, stability/modes model, lookup priority, freshness) live in
[../SKILL.md](../SKILL.md). This file holds capsule bodies — usage,
enablement, notes, sources — and stub pointers for features canonical in
another guide.

## Feature capsules

### id: kt22-guard-conditions

Area: Language

Use when:

- You need a `when` branch that matches a type or value and then checks an
  additional boolean condition without nesting another `if`.

Usage:

```kotlin
sealed interface Event
data class Login(val user: String, val trusted: Boolean) : Event
data object Logout : Event

fun route(event: Event): String = when (event) {
    is Login if event.trusted -> "trusted-login"
    is Login -> "login"
    Logout -> "logout"
}
```

Notes for agents:

- This is only for `when` expressions/statements with a subject.
- It improves readability over nested `if` blocks, but do not use it if the
  condition is long enough to obscure branch matching.

Source: https://kotlinlang.org/docs/whatsnew22.html

### id: kt22-non-local-break-continue

Area: Language

Use when:

- A loop body calls an inline function such as `forEach`, `run`, or `let`, and
  a nested lambda should `break` or `continue` the nearest enclosing loop.

Usage:

```kotlin
fun firstValid(lines: List<String>): String? {
    for (line in lines) {
        line.trim().run {
            if (isEmpty()) continue
            if (startsWith("#")) continue
            return this
        }
    }
    return null
}
```

Notes for agents:

- This works through inline lambdas only.
- Prefer ordinary loop control when the inline lambda makes control flow hard
  to see.

Source: https://kotlinlang.org/docs/whatsnew22.html

### id: kt22-multi-dollar-strings

Area: Language

Use when:

- A raw string contains many literal `$` characters, such as JSON Schema,
  shell snippets, templates, GraphQL, or docs examples.

Usage:

```kotlin
val propertyName = "count"

val schema = $$"""
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "required": ["$propertyName"],
  "example": "$$propertyName"
}
"""
```

Notes for agents:

- The number of `$` characters before the string controls how many `$`
  characters are needed to start interpolation.
- In `$$"""..."""`, single `$` stays literal; `$$name` interpolates.

Source: https://kotlinlang.org/docs/whatsnew22.html

### id: kt22-context-parameters

Area: Language

Carve-outs in 2.4.0-Beta2: basic context parameters are eap-stable with no
flag, but **callable references** with context parameters and **explicit
context argument passing** (`kt24-explicit-context-args`) remain
pre-stable. Context-sensitive resolution has its own feature status — see
`kt22-context-sensitive-resolution`.

Use when:

- You need dependency-style values available implicitly at call sites without
  making them global.
- Common examples: loggers, serializers, coroutine-ish scopes, request
  contexts, tracing, dependency contexts, capability objects.

Usage:

```kotlin
interface AuditLog {
    fun record(message: String)
}

context(audit: AuditLog)
fun createUser(name: String) {
    audit.record("create-user:$name")
}

fun run(log: AuditLog) {
    context(log) {
        createUser("ada")
    }
}
```

Enablement:

```kotlin
kotlin {
    compilerOptions {
        freeCompilerArgs.add("-Xcontext-parameters")
    }
}
```

Notes for agents:

- In 2.2 and 2.3, context parameters replace old context receivers, but stay
  pre-stable (Preview in 2.2, Experimental-evolving in 2.3).
- Prefer named context parameters. Anonymous `_` context parameters are useful
  only when the value is needed for resolution but not referenced directly.
- Avoid using context parameters as a hidden service locator. Keep them narrow
  and capability-like.
- For libraries, adding or removing context parameters is an API change.

Sources:

- https://kotlinlang.org/docs/whatsnew22.html
- https://kotlinlang.org/docs/whatsnew-eap.html

### id: kt22-context-sensitive-resolution

Area: Language

2.3.0 improvements (label also changes from Preview to Experimental):

- Sealed and enclosing supertypes of the current type are now part of the
  contextual scope.
- The compiler warns when context-sensitive resolution makes a resolution
  involving type operators or equalities ambiguous.

Use when:

- The expected type is obvious and repeating enum entries or sealed subclass
  qualifiers adds noise.

Usage:

```kotlin
enum class Mode { Read, Write }

fun open(mode: Mode) {}

fun demo() {
    open(Read)
}
```

Notes for agents:

- This is pre-stable. Do not use in published APIs unless the project already
  opts into it.
- It is most useful for enum entries and sealed hierarchies.
- If the code becomes ambiguous to a reader, prefer explicit qualification:
  `Mode.Read`.

Sources:

- https://kotlinlang.org/docs/whatsnew22.html
- https://kotlinlang.org/docs/whatsnew23.html

### id: kt22-contracts

Area: Language

2.2.20 additions: generics in contract type assertions, contracts inside
property accessors and selected operator functions, `returnsNotNull()`,
and a new `holdsIn` keyword for assuming conditions inside lambdas. The
2.2.0 and 2.3.0 "What's new" pages do not document new contract features;
2.2.20 is the source for everything below.

Use when:

- Writing low-level helper functions whose behavior should inform smart casts,
  initialization analysis, or call-in-place reasoning.

Enablement (2.2.20):

```kotlin
kotlin {
    compilerOptions {
        freeCompilerArgs.addAll(
            "-Xallow-contracts-on-more-functions",        // accessors, selected operators, generics
            "-Xallow-condition-implies-returns-contracts", // returnsNotNull / condition-implies-returns
            "-Xallow-holdsin-contract"                    // holdsIn keyword
        )
    }
}
```

Usage:

```kotlin
import kotlin.contracts.ExperimentalContracts
import kotlin.contracts.contract

@OptIn(ExperimentalContracts::class)
fun String?.isPresent(): Boolean {
    contract {
        returns(true) implies (this@isPresent != null)
    }
    return this != null && isNotBlank()
}
```

Notes for agents:

- Contracts are powerful but fragile. Use them in small, well-tested utility
  functions only.
- New 2.2.20 features additionally require `@OptIn(ExperimentalExtendedContracts::class)`
  on the call site that defines the contract.
- The flags above gate the *declaration* of the new contract shapes; the
  ambient `ExperimentalContracts` opt-in still applies to any `contract { }`
  block.

Source: https://kotlinlang.org/docs/whatsnew2220.html

### id: kt24-annotation-targets

Canonical capsule: [kotlin-2.4-eap-feature-guide.md](./kotlin-2.4-eap-feature-guide.md) → search for `### id: kt24-annotation-targets`.

### id: kt23-nested-type-aliases

Canonical capsule: [kotlin-2.3-feature-guide.md](./kotlin-2.3-feature-guide.md) → search for `### id: kt23-nested-type-aliases`.

### id: kt23-data-flow-exhaustiveness

Canonical capsule: [kotlin-2.3-feature-guide.md](./kotlin-2.3-feature-guide.md) → search for `### id: kt23-data-flow-exhaustiveness`.

### id: kt23-expression-body-return

Canonical capsule: [kotlin-2.3-feature-guide.md](./kotlin-2.3-feature-guide.md) → search for `### id: kt23-expression-body-return`.

### id: kt23-reified-catch

Canonical capsule: [kotlin-2.3-feature-guide.md](./kotlin-2.3-feature-guide.md) → search for `### id: kt23-reified-catch`.

### id: kt22-stdlib-codecs

Area: Standard library

`HexFormat` was originally introduced as Experimental in Kotlin 1.9.0;
2.2.0 promotes it (and the related hex parsing/formatting helpers) to
Stable. Code on Kotlin 1.9–2.1 already had access behind opt-in.

Use when:

- Encoding bytes as Base64 or formatting/parsing hex without third-party
  dependencies.

Usage:

```kotlin
import kotlin.io.encoding.Base64

fun encodeToken(bytes: ByteArray): String = Base64.UrlSafe.encode(bytes)
```

```kotlin
import kotlin.text.HexFormat
import kotlin.text.toHexString

fun id(bytes: ByteArray): String =
    bytes.toHexString(HexFormat { bytes.byteSeparator = "-" })
```

Notes for agents:

- The 2.2 release stabilizes these APIs, so new Kotlin 2.2+ code should not
  need the older encoding opt-in for the stabilized surface.
- Prefer stdlib codecs over custom byte/string conversions.

Source: https://kotlinlang.org/docs/whatsnew22.html

### id: kt22-stdlib-experimental-misc

Area: Standard library

Surface added in 2.2.20: `KClass.isInterface`, `AtomicInt.update()` and
related atomic update helpers, and common `copyOf()` overloads that
initialize extra array elements.

Use when:

- Reflection-like code needs to check whether a `KClass` represents an
  interface in common code.
- Atomic variables need concise compare-and-update loops.
- Array copies should fill newly created slots during copying.

Usage:

```kotlin
import kotlin.concurrent.atomics.AtomicInt
import kotlin.concurrent.atomics.ExperimentalAtomicApi

@OptIn(ExperimentalAtomicApi::class)
fun increment(counter: AtomicInt): Int =
    counter.updateAndFetch { it + 1 }
```

Notes for agents:

- These are experimental in 2.2.20; do not use in stable API surfaces without
  opt-in policy.

Source: https://kotlinlang.org/docs/whatsnew2220.html

### id: kt22-compiler-warning-level

Area: Compiler

Use when:

- A module needs to raise, restore, or suppress one diagnostic without changing
  the global warning policy.
- A project wants `-Werror` but must keep selected diagnostics as warnings.

Usage:

```kotlin
compilerOptions {
    allWarningsAsErrors = true
    freeCompilerArgs.add("-Xwarning-level=DIAGNOSTIC_NAME:warning")
}
```

Notes for agents:

- Syntax: `-Xwarning-level=DIAGNOSTIC_NAME:(error|warning|disabled)`.
- This controls warning severity only; it does not enable unrelated compiler
  analyses by itself.
- Experimental in 2.2.x. Prefer existing project warning policy unless the user
  is explicitly tuning diagnostics.

Source: https://kotlinlang.org/docs/whatsnew22.html

### id: kt22-jvm-default

Area: JVM / Compiler

Behavior change in 2.2.0: the default `-jvm-default` mode changed from
`disable` to `enable`.

Use when:

- Interfaces need real JVM default methods.
- Library authors need to control backward compatibility strategy for
  `DefaultImpls` generation.

Gradle usage:

```kotlin
kotlin {
    compilerOptions {
        jvmDefault = JvmDefaultMode.ENABLE
    }
}
```

Notes for agents:

- `enable`: generate default methods in interfaces and keep compatibility with
  old implementations where needed.
- `no-compatibility`: generate only default methods, without compatibility
  scaffolding.
- `disable`: old behavior; deprecated.
- Library maintainers should review ABI compatibility before switching modes.

Source: https://kotlinlang.org/docs/whatsnew22.html

### id: kt22-jvm-annotations-metadata

Area: JVM / Metadata

Use when:

- Tools, processors, or metadata readers need annotation data from Kotlin
  metadata, not only JVM bytecode locations.

Build usage for 2.2/2.3:

```kotlin
compilerOptions {
    freeCompilerArgs.add("-Xannotations-in-metadata")
}
```

Notes for agents:

- Metadata consumer code must opt into the corresponding
  `ExperimentalAnnotationsInMetadata` APIs in `kotlin-metadata-jvm`.
- In 2.4.0-Beta2, the compiler writes annotations to metadata by default.
- Tooling should tolerate both old and new metadata layouts when supporting
  mixed Kotlin versions.

Sources:

- https://kotlinlang.org/docs/whatsnew22.html
- https://kotlinlang.org/docs/whatsnew-eap.html

### id: kt22-jvm-expose-boxed

Area: JVM / Java interop

Use when:

- Java callers need ergonomic access to Kotlin inline value classes without
  manually dealing with mangled or implementation-specific members.

Usage:

```kotlin
@JvmInline
value class UserId(val value: String)

data class User(val id: UserId)

class UserService {
    @JvmExposeBoxed
    fun load(id: UserId): User = User(id)
}
```

Build:

```kotlin
compilerOptions {
    freeCompilerArgs.add("-Xjvm-expose-boxed")
}
```

Notes for agents:

- Use on API points intended for Java consumers.
- Do not turn this on blindly for all value classes in performance-sensitive
  code; boxed bridges affect bytecode surface.

Source: https://kotlinlang.org/docs/whatsnew22.html

### id: kt22-jvm-invokedynamic-when

Area: JVM / Compiler

Use when:

- A JVM-targeted project wants smaller bytecode for supported `when`
  expressions and runs on JVM target 21 or newer.

Build:

```kotlin
compilerOptions {
    jvmTarget.set(JvmTarget.JVM_21)
    freeCompilerArgs.add("-Xwhen-expressions=indy")
}
```

Notes for agents:

- Applies to `when` over types and null checks.
- Source-stated requirements: subject must be present (no subjectless `when`),
  no guard conditions, and the branch types must not include mutable
  collections or function types. The expression must have **at least two
  conditions besides `else`** — multiple conditions are required, not
  forbidden.
- Experimental; benchmark and inspect bytecode only if this matters.

Source: https://kotlinlang.org/docs/whatsnew2220.html

### id: kt22-mpp-cross-platform-klib

Area: Multiplatform / Library publishing

Use when:

- Publishing multiplatform libraries where a single klib can be reused across
  supported native targets.

Notes for agents:

- Check target compatibility and publication layout before changing an
  existing library.
- This reduces target-specific klib duplication but does not remove all native
  platform differences.

Source: https://kotlinlang.org/docs/whatsnew2220.html

### id: kt22-mpp-common-dependencies

Area: Multiplatform / Gradle

Requires Gradle 8.8+ per the source page; older Gradle versions will not
expose the DSL.

Use when:

- A dependency belongs to the common source set and should be declared without
  locating or naming `commonMain` explicitly.

Usage:

```kotlin
kotlin {
    @OptIn(org.jetbrains.kotlin.gradle.ExperimentalKotlinGradlePluginApi::class)
    dependencies {
        implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2")
    }
}
```

Notes for agents:

- Experimental Gradle DSL. Prefer existing project style unless the project is
  already adopting the new DSL.

Source: https://kotlinlang.org/docs/whatsnew2220.html

### id: kt22-native-swift-export

Area: Native / Apple interop

Per-version detail:

- 2.3.0 adds native enum-class mapping and variadic function parameter
  export.
- 2.4.0-Beta2 adds Swift package import (`kt24-native-swift-package-import`)
  and Flow → AsyncSequence export (`kt24-native-swift-flow-export`).

Use when:

- A Kotlin Multiplatform module should expose APIs to Swift without going
  through Objective-C headers as the primary interface.

Usage shape:

```kotlin
kotlin {
    iosArm64()
    iosSimulatorArm64()

    swiftExport {
        moduleName = "SharedKit"
    }
}
```

Notes for agents:

- Still experimental. Do not assume stable ABI/source compatibility.
- Favor simple Kotlin API surfaces for Swift: explicit nullability, data
  classes where supported, minimal generics, and predictable names.
- Kotlin 2.3.0 improves enum and vararg export, but test generated Swift
  carefully.

Sources:

- https://kotlinlang.org/docs/whatsnew2220.html
- https://kotlinlang.org/docs/whatsnew23.html
- https://kotlinlang.org/docs/whatsnew-eap.html

### id: kt22-native-memory

Area: Native / Runtime

Per-version detail:

- 2.2.0: Apple targets use the tagged memory allocator by default;
  per-object memory allocation is experimental
  (`kotlin.native.binary.pagedAllocator=false`); Latin-1 string support is
  experimental (`kotlin.native.binary.latin1Strings=true`).
- 2.2.20: stack canaries via the `stackProtector` binary option are stable;
  smaller release binaries are experimental
  (`kotlin.native.binary.smallBinary=true`).

Use when:

- Tuning Native memory behavior, binary size, or diagnostics.

Gradle properties:

```properties
kotlin.native.binary.pagedAllocator=false
kotlin.native.binary.latin1Strings=true
```

Binary option shape:

```kotlin
kotlin {
    linuxX64 {
        binaries {
            executable {
                binaryOption("stackProtector", "strong")
                binaryOption("smallBinary", "true") // 2.2.20, Experimental
            }
        }
    }
}
```

Notes for agents:

- These are runtime/build tuning options. Add benchmarks and platform tests.
- Do not enable experimental allocator/string/binary-size options in libraries
  without explicit project policy.

Sources:

- https://kotlinlang.org/docs/whatsnew22.html
- https://kotlinlang.org/docs/whatsnew2220.html

### id: kt22-wasm-target-split

Area: Wasm / Multiplatform

Use when:

- Configuring projects for browser/JavaScript-hosted Wasm versus WASI-hosted
  Wasm.

Usage:

```kotlin
kotlin {
    wasmJs {
        browser()
    }
    wasmWasi {
        nodejs()
    }
}
```

Notes for agents:

- Choose `wasmJs` for browser and JS host interop.
- Choose `wasmWasi` for WASI environments.

Source: https://kotlinlang.org/docs/whatsnew22.html

### id: kt22-wasm-beta

Area: Wasm

2.2.20 additions: separate npm dependencies, common `webMain`, improved
browser debugging, and JavaScript exception interop.

Use when:

- Starting or upgrading Kotlin/Wasm projects with a stronger compatibility
  expectation than pre-Beta releases.

Usage:

```kotlin
kotlin {
    wasmJs {
        browser()
        binaries.executable()
    }
}
```

Notes for agents:

- Beta is still not final stable. Check browser/runtime/tooling support.
- `webMain` can share code between JS and Wasm web targets.

Source: https://kotlinlang.org/docs/whatsnew2220.html

### id: kt22-js-export-plain-object

Area: JavaScript / Export interop

2.2.0 surface: stable `copy()` for `@JsPlainObject` interfaces; type
aliases in `@JsModule`; `@JsExport` on `expect` declarations; exporting
functions returning `Promise<Unit>`. `LongArray`/`BigInt64Array` export
is **not** part of this capsule — see `kt23-js-longarray-bigint`
(introduced in 2.3.0 with `-Xes-long-as-bigint`).

Use when:

- Kotlin/JS exports typed plain JS objects or APIs to TypeScript/JavaScript.

Usage:

```kotlin
@JsPlainObject
external interface UserOptions {
    val name: String
    val retries: Int
}

fun withRetries(options: UserOptions): UserOptions =
    options.copy(retries = 3)
```

Notes for agents:

- `@JsPlainObject` is for external plain object shape interop.
- Keep exported APIs simple and TypeScript-friendly.

Sources:

- https://kotlinlang.org/docs/whatsnew22.html
- https://kotlinlang.org/docs/whatsnew2220.html

### id: kt22-js-bigint-long

Area: JavaScript

Requires the ES2020 JS target per the source page; the flag has no effect
on older targets.

Use when:

- Kotlin `Long` values should map to JavaScript `BigInt` in generated JS.

Build:

```kotlin
compilerOptions {
    freeCompilerArgs.add("-Xes-long-as-bigint")
}
```

Notes for agents:

- Requires runtime environments that support `BigInt`.
- Check TypeScript declarations and external JS consumers before enabling.

Source: https://kotlinlang.org/docs/whatsnew2220.html

### id: kt22-gradle-abi-validation

Area: Gradle / Library publishing

Use when:

- A library project wants public ABI checks integrated into the Kotlin Gradle
  plugin.

Usage shape:

```kotlin
kotlin {
    abiValidation {
        enabled = true
    }
}
```

Notes for agents:

- Task names and behavior evolved between 2.2 and 2.3.20.
- Run the ABI check task after changing public APIs.
- Do not add ABI validation to application-only projects unless requested.

Sources:

- https://kotlinlang.org/docs/whatsnew22.html
- https://kotlinlang.org/docs/whatsnew2320.html

### id: kt22-gradle-compiler-schema

Area: Gradle / Compiler options

No source-side action — see `status-index.md` for status. Use the typed
Gradle compiler-option DSL; the schema is for tooling, not a reason to
add raw `freeCompilerArgs`.

Source: https://kotlinlang.org/docs/whatsnew2220.html

### id: kt22-gradle-bta

Area: Gradle / Build tools API

No source-side action — see `status-index.md` for status. Most users do
not configure this directly.

Source: https://kotlinlang.org/docs/whatsnew22.html

### id: kt22-maven-daemon

Area: Maven

No source-side action — see `status-index.md` for status. Build behavior
change only.

Source: https://kotlinlang.org/docs/whatsnew2220.html

### id: kt22-compose-compiler

Area: Compose compiler

Per-version detail:

- 2.2.0: functional references to composable functions; `PausableComposition`
  and `OptimizeNonSkippingGroups` enabled by default.
- 2.2.20: language-version restrictions for default parameters, composable
  target warnings under K2, fully qualified names in build metrics.
- 2.3.0: ProGuard mappings extend the experimental Compose stack-trace
  feature from debuggable variants to R8-minified release builds. Kotlin
  docs do not call this "source mapping".

Use when:

- Updating Compose projects with the Kotlin-bundled Compose compiler.

Notes for agents:

- Check Compose runtime/compiler compatibility as a pair.
- Re-run UI tests and inspect recomposition/performance-sensitive paths after
  Kotlin compiler upgrades.
- The 2.3.0 ProGuard-mappings feature is part of the experimental Compose
  stack-trace support; only enable in projects that already opt in.

Sources:

- https://kotlinlang.org/docs/whatsnew22.html
- https://kotlinlang.org/docs/whatsnew2220.html
- https://kotlinlang.org/docs/whatsnew23.html
