# Kotlin 2.4 EAP feature guide for agents

Target: Kotlin 2.4.0-Beta2 EAP. **Always load `kt24-eap-guardrails` before
recommending Kotlin 2.4 for production code.** `eap-stable` means stable
in the EAP docs, not in a final GA release.

For stability/mode, use [status-index.md](./status-index.md) (sole source
of truth). Shared rules (verified date, stability/modes model, lookup
priority, freshness) live in [../SKILL.md](../SKILL.md). This file holds
capsule bodies — usage, enablement, notes, sources — and stub pointers
for features canonical in another guide.

## Feature capsules

### id: kt24-eap-guardrails

Area: Release management

Status:

- Kotlin 2.4.0-Beta2 is EAP. See `metadata.verified` and `Freshness` in
  `../SKILL.md` for when this was last checked and when to reverify.

Use when:

- Any agent plans to recommend, configure, or generate code for Kotlin 2.4.

Rules:

- Say "Kotlin 2.4.0-Beta2" or "2.4 EAP" unless final 2.4.0 has been verified.
- Do not call 2.4 production-stable before checking final release docs.
- Features marked eap-stable in this file are stable according to the EAP docs,
  not according to a final GA release.
- For production projects, prefer Kotlin 2.3.x stable unless the user explicitly
  wants EAP features or is already on an EAP train.
- Re-check source links before generating final 2.4-specific guidance.

Source: https://kotlinlang.org/docs/whatsnew-eap.html

### id: kt22-context-parameters

Canonical capsule: [kotlin-2.2-feature-guide.md](./kotlin-2.2-feature-guide.md) → search for `### id: kt22-context-parameters`.

### id: kt24-annotation-targets

Area: Language / JVM interop

Use when:

- A JVM annotation must be propagated to several generated Java elements
  consistently.
- Frameworks inspect constructor parameters, fields, getters, setters, record
  components, or property targets differently.

Usage:

```kotlin
data class User(
    @all:NotBlank
    val name: String
)
```

Build flags for 2.2/2.3:

```kotlin
compilerOptions {
    freeCompilerArgs.addAll(
        "-Xannotation-target-all",
        "-Xannotation-default-target=param-property"
    )
}
```

Notes for agents:

- `@all:` is a meta-target: the compiler expands it to all applicable targets.
- With the new defaulting rule, an unqualified annotation can be emitted to
  `param`, `property`, and `field` instead of selecting only the first
  applicable target.
- In 2.4.0-Beta2 these no longer require flags. Reverify for final 2.4.0.

Sources:

- https://kotlinlang.org/docs/whatsnew22.html
- https://kotlinlang.org/docs/whatsnew-eap.html

### id: kt24-explicit-backing-fields

Area: Language

Use when:

- A public property should expose a restricted type while its backing field
  uses a more specific mutable type.
- Common case: exposing `StateFlow<T>` while storing `MutableStateFlow<T>`.

Usage:

```kotlin
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

class ProfileModel {
    val name: StateFlow<String>
        field = MutableStateFlow("")

    fun rename(value: String) {
        name.value = value
    }
}
```

Notes for agents:

- The declared property type remains the API surface.
- Inside the property's private scope, Kotlin can access the backing field's
  more specific type.
- Good fit for read-only public APIs backed by mutable internals.

Sources:

- https://kotlinlang.org/docs/whatsnew23.html
- https://kotlinlang.org/docs/whatsnew-eap.html

### id: kt24-explicit-context-args

Area: Language

Use when:

- A call should pass context parameters explicitly instead of relying on
  implicit resolution from surrounding scope.

Usage:

```kotlin
context(config: Config)
fun connect(): Client = Client(config.url)

fun open(config: Config): Client = connect(config)
```

Notes for agents:

- This depends on context parameters.
- Use explicit arguments to improve readability when multiple context values of
  the same shape are available.
- Still experimental in the 2.4 EAP.

Source: https://kotlinlang.org/docs/whatsnew-eap.html

### id: kt24-collection-literals

Area: Language / Standard library interop

Use when:

- List/set/map-like values should be expressed compactly and the project
  accepts experimental syntax.

Usage:

```kotlin
val names: List<String> = ["ada", "grace"]
val aliases: Set<String> = ["root", "admin"]
val empty: List<Int> = []
```

Custom collection-like types:

```kotlin
class NonEmptyList<T> private constructor(private val values: List<T>) {
    companion object {
        operator fun <T> of(vararg values: T): NonEmptyList<T> {
            require(values.isNotEmpty())
            return NonEmptyList(values.toList())
        }
    }
}

val ids: NonEmptyList<Int> = [1, 2, 3]
```

Notes for agents:

- Without an expected type, non-empty literals default to `List`.
- The feature currently cannot construct Java collections directly.
- The syntax is pre-stable; do not introduce it into conservative production
  projects.

Source: https://kotlinlang.org/docs/whatsnew-eap.html

### id: kt24-compile-time-constants

Area: Language / Compiler

Use when:

- `const val` initialization needs compiler-evaluable unsigned arithmetic,
  string operations, enum or callable properties, or other supported pure
  intrinsic operations.

Usage:

```kotlin
const val endpoint = "users".uppercase()
const val mask = 1u shl 3
```

Notes for agents:

- The compiler evaluates only a supported set of operations.
- Do not assume arbitrary function calls are compile-time evaluable.
- Keep constants simple for library ABI readability.

Source: https://kotlinlang.org/docs/whatsnew-eap.html

### id: kt23-stdlib-uuid

Canonical capsule: [kotlin-2.3-feature-guide.md](./kotlin-2.3-feature-guide.md) → search for `### id: kt23-stdlib-uuid`.

### id: kt24-stdlib-sorted-order

Area: Standard library

Use when:

- Code needs a clear way to express ascending or descending sort order.

Usage:

```kotlin
data class User(val name: String, val age: Int)

fun alreadySorted(users: List<User>): Boolean =
    users.isSortedBy(User::age)
```

Notes for agents:

- The 2.4 EAP introduces `isSorted()` and `isSortedBy()` style APIs for
  checking sorted order.
- Confirm exact names and package imports against final 2.4 docs before
  writing final production code.

Source: https://kotlinlang.org/docs/whatsnew-eap.html

### id: kt24-stdlib-unsigned-bigint

Area: Standard library

Use when:

- Unsigned common values need conversion to `java.math.BigInteger` on JVM or to
  the corresponding common BigInteger API available to the project.

Usage:

```kotlin
val size = UInt.MAX_VALUE.toBigInteger()
val huge = ULong.MAX_VALUE.toBigInteger()
```

Notes for agents:

- Reverify final package/import names in 2.4 final docs before generating code.

Source: https://kotlinlang.org/docs/whatsnew-eap.html

### id: kt22-jvm-annotations-metadata

Canonical capsule: [kotlin-2.2-feature-guide.md](./kotlin-2.2-feature-guide.md) → search for `### id: kt22-jvm-annotations-metadata`.

### id: kt23-jvm-java-versions

Canonical capsule: [kotlin-2.3-feature-guide.md](./kotlin-2.3-feature-guide.md) → search for `### id: kt23-jvm-java-versions`.

### id: kt24-native-swift-package-import

Area: Native / Apple interop

Use when:

- Kotlin/Native code needs to consume Swift packages through Swift Package
  Manager integration.

Notes for agents:

- This is EAP. Expect Gradle/Xcode/SPM edge cases.
- Use only when the project already depends on Swift packages and native
  interop tests can run on Apple toolchains.

Source: https://kotlinlang.org/docs/whatsnew-eap.html

### id: kt24-native-swift-flow-export

Area: Native / Swift export

Use when:

- Swift clients should consume Kotlin `Flow` values as Swift `AsyncSequence`.

Notes for agents:

- Part of the 2.4 EAP Swift export work. Treat as pre-final until 2.4.0
  final docs are verified.
- Check coroutine cancellation, backpressure, threading, and lifetime
  behavior from Swift tests.

Source: https://kotlinlang.org/docs/whatsnew-eap.html

### id: kt24-native-gc-cms

Area: Native / Runtime

No source-side action — see `status-index.md` for status. Opt out with
`kotlin.native.binary.gc=pmcs`.

Source: https://kotlinlang.org/docs/whatsnew-eap.html

### id: kt24-native-klib-inlining

Area: Native / Compiler

No source-side action — see `status-index.md` for status. Intra-module
klib inlining is the new default; full cross-module mode is opt-in via
`-Xklib-ir-inliner=full`. Library authors should run ABI/binary-size
checks after upgrading.

Source: https://kotlinlang.org/docs/whatsnew-eap.html

### id: kt24-wasm-incremental

Area: Wasm / Compiler

No source-side action — see `status-index.md` for status. Disable with
`kotlin.incremental.wasm=false` if needed.

Source: https://kotlinlang.org/docs/whatsnew-eap.html

### id: kt24-wasm-component-model

Area: Wasm / Interop

Use when:

- Exploring the WebAssembly Component Model from Kotlin/Wasm.

Notes for agents:

- This is experimental EAP functionality. Do not use for production libraries
  unless explicitly requested.
- Expect target and tooling restrictions.

Source: https://kotlinlang.org/docs/whatsnew-eap.html

### id: kt24-js-value-class-export

Area: JavaScript / Export interop

Use when:

- Exporting Kotlin value classes to JavaScript/TypeScript APIs.

Usage:

```kotlin
@JvmInline
value class UserId(val value: String)

@JsExport
fun loadUser(id: UserId): String = id.value
```

Notes for agents:

- Treat as pre-final until 2.4.0 final docs are checked.
- Check generated JS and `.d.ts` files before publishing.

Source: https://kotlinlang.org/docs/whatsnew-eap.html

### id: kt24-js-es2015-incremental

Area: JavaScript / Compiler

No source-side action — see `status-index.md` for status.

Source: https://kotlinlang.org/docs/whatsnew-eap.html

### id: kt24-maven-jvm-target-alignment

Area: Maven / JVM

Use when:

- Maven Kotlin and Java compile tasks need consistent JVM target settings.

Notes for agents:

- This is mainly a build consistency improvement.
- Reverify exact configuration behavior in final 2.4 docs before changing
  production Maven builds.

Source: https://kotlinlang.org/docs/whatsnew-eap.html
