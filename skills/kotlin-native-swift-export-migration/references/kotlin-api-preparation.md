# Preparing the Kotlin side for Swift Export

## Core rule

Swift Export exports **every public declaration** of the exported module(s) — referenced from Swift or not —
and pulls in dependency libraries as far as they are reachable from that public API (plus everything of direct
`api` dependencies). Like ObjC export, it doesn't prune public declarations that Swift never references; unlike
ObjC export, there's no `export()` list — you control the surface with visibility, `api`/`implementation`, and
`SwiftExportVisibility`.

Consequences: a large public surface means long Swift Export runs, huge generated code, more exporter bugs
from third-party libraries (serialization, SQLDelight, Ktor, Koin...), and a confusing Swift API.
Real-world result (PeopleInSpace): making DI/HTTP/DB code internal and keeping the DB module out of the export took
it from 17 Swift modules / 18k lines to 7 modules / 6.7k lines and removed every exporter failure.

## Step 1 — remove ObjC-export-era tooling

| Tool | Action |
|---|---|
| SKIE (`co.touchlab.skie`) | remove plugin + `skie {}` config (or `skie { isEnabled = false }` temporarily). Replace its Swift helpers (`onEnum`, `Observing`, flows/suspend bridging) per `swift-call-site-rewrites.md` R24–R27. SKIE often pins the Kotlin version — removing it unblocks upgrades. |
| KMP-NativeCoroutines | **Keep it, in Swift Export compatibility mode** — the migration path its author documents (github.com/rickclephas/KMP-NativeCoroutines/blob/master/SWIFT_EXPORT.md). (1) Bump the Gradle plugin (and its KSP) to preflight's `KMPNC_FOR_TARGET`: for a stable target Kotlin the newest plain release whose release notes name that Kotlin; for a pre-release the matching `-kotlin-<version>` build (e.g. `1.0.7-kotlin-2.5.0-RC`, verified on 2.5.0-RC2). (2) Add `nativeCoroutines { swiftExport = true }` to the module's `build.gradle.kts`. (3) Keep all `@NativeCoroutines`/`@NativeCoroutinesState`/`@NativeCoroutineScope` annotations: the plugin clones the annotated declarations so Kotlin keeps compiling, and Swift Export publishes them under the original names as typed flows (`KotlinTypedMutableStateFlow<T>`), plus the `xxxValue` properties. (4) Swift: `asyncSequence(for:)` / `asyncFunction(for:)` keep compiling as deprecated no-op shims (a deprecation warning per call is expected); the Combine/RxSwift helpers (`createPublisher`, `createFuture`, `createObservable`, `createSingle`) need a small rewrite (`swift-call-site-rewrites.md` R25). `NativeFlow`/`NativeSuspend` types are unsupported; on cancellation Swift Export throws `CancellationError` instead of ending the iteration. This deviates on purpose from the draft official migration guide (which removes KMP-NC up front): it keeps the diff small and is the path KMP-NC documents. **Later, optional cleanup** (separate step, or in Phase 5 when the user asks to drop KMP-NC): replace the shims with `flow.asAsyncSequence()` / `try await fn()` (follow the deprecation warnings), then remove the annotations, the plugin, its KSP and the Swift packages. No release for the target Kotlin → a Phase 0 decision (wait for one, use a Kotlin it supports, or drop KMP-NC up front); never removed without the user's approval. |
| `kotlin("native.cocoapods")` | not supported. As a **separate step before** the Swift Export switch, run the `kotlin-tooling-cocoapods-spm-migration` skill (same repository: https://github.com/Kotlin/kotlin-agent-skills/tree/main/skills/kotlin-tooling-cocoapods-spm-migration): it replaces `pod()` dependencies with `swiftPMDependencies {}`, moves Xcode to the direct integration (Run Script with `embedAndSignAppleFrameworkForXcode`), deintegrates CocoaPods and removes the plugin. Build and run the app, then continue with this skill. |
| XCFramework / SPM packaging and publishing (`multiplatform-swiftpackage`, KMMBridge, custom `assembleXCFramework` publishing) | **always a Phase 0 decision** — it usually publishes to consumers outside the repo (e.g. a remote Swift package repo). Options: keep it (then keep `binaries.framework` next to `export { }` for it; never link both into one Xcode target), replace it with `swiftPackageIntegration()` on `<EXPORT_MODULE>` (`gradle-and-xcode.md` §4), or remove it and report its consumers. Never on your own. |
| Hacks for ObjC: dummy `@Throws` functions to force a type into the header, `@ObjCName` only to fix ObjC mangling, `doInit`-avoiding renames, `@HiddenFromObjC` on Kotlin-only API | review: dummy exporters can go (all public types are exported); `@ObjCName(swiftName=)` still renames in Swift; `@HiddenFromObjC` still hides from Swift Export. |
| Compiler plugins that generate **public** declarations (Koin annotations/compiler plugin `module()` extensions, some serialization/DI/codegen) | check the generated Swift for `invalid redeclaration` or unavailable stubs; make the generated API non-public or upgrade the plugin (check its latest releases); replacing it with hand-written internal code (e.g. Koin DSL `internal val appModule = module { ... }`) needs the **user's permission** — SKILL.md Phase 1 step 3. |
| KSP processors | upgrade to a version compatible with the new Kotlin; pin transitive KSP versions if a plugin drags an old one. |

## Step 2 — name modules, then shrink the exported surface

Items 1–4 only when something forces them: the Swift Export build fails in your module or runs out of memory, or
the exported surface is huge. After **any** visibility change, build the non-iOS consumers of `<SHARED_MODULE>`
right away (`./gradlew <SHARED_MODULE>:compileKotlinJvm`, `:<androidApp>:assembleDebug`, `:<desktop>:compileKotlin`,
... — SKILL.md Phase 6 step 3): `internal` breaks code in other modules that used those declarations.

0. **Name every exported Gradle module in its own build file** —
   `kotlin { export { @OptIn(ExperimentalSwiftExportDsl::class) swift { moduleName = "Models"; rootPackage = "com.example.models" } } }`.
   Otherwise its Swift module name is derived from Gradle coordinates (long). Prefer this over `configure()` overrides
   in the umbrella module.
1. **Make non-Swift-facing code `internal`**: DI modules, repositories implementations, HTTP clients, mappers,
   DB wrappers, utility extensions. `internal` is module-wide, so other platforms in the same module still see
   it; code in *other* modules (Android app, desktop) that used those types must switch to public interfaces.
2. **Consider `explicitApi()`** in exported modules (`kotlin { explicitApi() }`) so every public declaration is a
   deliberate choice; it also forces explicit return types (good: typed `StateFlow<UiState>` instead of an
   inferred chain).
3. **Mark dependencies used only internally as `implementation`, not `api`** (`api` deps are exported fully). If
   their types still leak into the public API, hide them (item 5) — hidden modules become shallow, member-less stubs.
4. **Consider keeping library types out of public signatures** (smaller API, faster builds, smaller binary):
   - public type + `internal constructor(client: HttpClient)` when Swift needs the type but not its construction;
   - return `Unit`/own types from Swift-facing entry points (`fun initKoin()` instead of returning
     `KoinApplication`); put library-typed overloads in non-Apple source sets
     (`androidMain`/`jvmMain`) or mark them `@HiddenFromObjC`;
   - drop library supertypes from public classes (`: KoinComponent`) — inject via constructor instead;
   - expose an interface + top-level factory, keep the implementation `internal`:
     ```kotlin
     interface FeatureApi { fun state(): StateFlow<State>; suspend fun refresh() }
     fun featureApi(): FeatureApi = DefaultFeatureApi()       // internal class DefaultFeatureApi
     ```
5. **Hide dependencies** whose types leak but Swift doesn't need, or whose export still breaks through the
   umbrella: `hiding-broken-dependencies.md` (hidden types trap at runtime unless wrapped).

## Step 3 — reshape constructs Swift Export can't express well

| Kotlin pattern | Problem in Swift Export | Do this |
|---|---|---|
| `fun f(list: MutableList<T>)`, `MutableSet`/`MutableMap` params | mutable collection types are not supported | use read-only `List`/`Set`/`Map` params |
| custom classes implementing `List`/`Set`/`Map` | bridge compiles, but Swift can't instantiate the type | expose a wrapper type or a read-only collection supertype |
| params typed `Box<String>` (generic class with concrete type arg) | function silently not exported | take `Box<*>`/the upper bound, or a non-generic wrapper type |
| default arguments used from Swift | not exported | add explicit overloads / secondary constructors for the Swift call shapes |
| `inline fun <reified T>` | not exported | add a non-reified variant (`KClass<T>` parameter) |
| `vararg` called with dynamic arrays from Swift | Swift variadic can't take an array | add a `List<T>` overload |
| `protected` members needed by Swift subclasses | invisible | make them public (or a public accessor) |
| `@ShouldRefineInSwift` | ignored | rename/hide: make it internal + public Swift-friendly variant, or accept it's visible |
| completion-handler-shaped API (`fun load(callback: (Result) -> Unit)`) | awkward in Swift | expose plain `suspend fun` / `Flow` — Swift gets `async throws` / `asAsyncSequence()` |
| `@NativeCoroutines suspend fun` / `@NativeCoroutinesState val state: StateFlow<T>` | **keep the annotations during the migration** (compatibility mode, Step 1). Only in the later KMP-NC cleanup do they become redundant | in that cleanup: drop the annotation, keep `suspend fun` / `val state: StateFlow<T>` (typed `KotlinTypedStateFlow<T>`, `.value`); explicit type |
| `Flow<T>` built through generic helpers | element type may erase to `_KotlinBridgeable` | declare the property/function type explicitly (`val items: Flow<List<Item>>`) |
| member **properties** named `description`, `debugDescription`, `hash`, `hashValue`, `superclass` (also `val description` in a data class constructor) | dropped: Swift silently reads the inherited `NSObject` property instead (KT-90497, as designed) | rename in Kotlin (`summary`) or `@ObjCName(swiftName = "description_")` |
| function named `init` | ObjC export renamed it `doInit`; confusing next to Swift initializers | rename in Kotlin (`start`) |
| exceptions thrown from non-suspend functions | terminate the app when they reach Swift | annotate with `@Throws(...)` |
| Generic sealed interface consumed by `switch` in Swift | no `sealedType()` | make it a sealed class, or non-generic, or accept `as?` casts |
| `class X : NSObject()` / Kotlin implementing ObjC protocols, consumed by Swift | not exported | expose a Kotlin interface instead, or return the platform type (`UIViewController`) |
| C structs / CEnum / `NSTimeInterval`-typed API | unavailable | wrap in Kotlin types/primitives |
| generic classes / interfaces / sealed states in the Swift-facing API (`ScreenState<T>`, `Result<T>`, `Repository<T>`) | erased payloads (casts), functions taking `X<Concrete>` not exported, `List<X<Concrete>>` params break the build, generic sealed interfaces have no `sealedType()` | non-generic wrappers mapped in Kotlin: mirror sealed class (`ProfileState`), concrete subclass/sub-interface with `override`s (`ProfileRepository : Repository<Profile>`), concrete facade functions — `wrapping-generics.md` |
| Kotlin types named like Swift/SwiftUI types (`Shape`, `Color`, `Text`, `Hasher`, `Result`, `Error`, `Task`) | ambiguous in Swift files importing SwiftUI/Foundation (worse with `rootPackage`) | rename (`Figure`, `TextHasher`) or `@ObjCName(swiftName=)` |
| Swift must create a Kotlin `Flow`/`MutableStateFlow` (Swift implements an interface with flow members) | Swift can't construct Kotlin flows; kotlinx factories are generic/erased | export typed builders: `fun mutableStateFlow(initial: String): MutableStateFlow<String>` |
| Kotlin interface implemented in Swift | supported (cross-language inheritance; the Swift class inherits `KotlinBase` or an exported Kotlin `open class`) | keep, update Swift (R28). Kotlin must not rely on the impl being a particular Kotlin class |
| Kotlin `Any`/`T` params called from Swift with numbers | Swift `Int` literal becomes `Double` | prefer concrete types in Swift-facing API |
| `internal` types in public `sealed` hierarchies | `.unknown` case in `sealedType()` | make the Swift-relevant subclasses public |
| Opt-in (`@RequiresOptIn`) API needed in Swift | exported as `@_spi(...)` | `@_spi(Marker) import <BASENAME>` in Swift, or a non-opt-in wrapper |
| exported declarations using opt-in APIs of a dependency (e.g. kotlinx-datetime) | export needs the opt-in | module-level `compilerOptions { optIn.add("kotlin.time.ExperimentalTime") }` in the exporting module |

## Step 4 — giving Kotlin access to Swift-only APIs (two options)

Swift-only capabilities (CryptoKit, Keychain/Security, StoreKit, HealthKit, SwiftUI views, Swift packages without
ObjC API) can't be called from Kotlin directly. Under ObjC export this was usually an interface implemented in Swift;
with Swift Export there are two supported options. Both pass a Swift implementation into the Kotlin world, and Kotlin
calls it back.

**Option A — function types (closures).** Kotlin declares a function-typed parameter or a small class holding
function-typed properties; Swift passes closures.
```kotlin
class TextHasher(val hash: (String) -> String)
fun fingerprint(text: String, hasher: TextHasher): String = "$text#${hasher.hash(text)}"
// suspend variant: class TokenProvider(val fetch: suspend () -> String)   → Swift: { () async throws -> String in ... }
```
```swift
import CryptoKit
let md5 = TextHasher(hash: { input in
    Insecure.MD5.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
})
fingerprint(text: "kotlin", hasher: md5)
```
Best for one or a few operations, stateless helpers, and DI-style "platform services" built in one place. No
Swift subclass needed.

**Option B — Kotlin interface implemented in Swift** (cross-language inheritance, see
kotlinlang.org/docs/native-swift-export.html#cross-language-inheritance). Kotlin declares an interface (it can have
`suspend` functions, `Flow`/`StateFlow` properties and default methods); Swift implements it with a class that
inherits a Kotlin superclass — `KotlinBase`, or an exported Kotlin `open class SwiftBase` as in the docs — and
passes the instance back; Kotlin code depends only on the interface.
```kotlin
interface SecureStorage { fun read(key: String): String?; fun write(key: String, value: String); suspend fun wipe() }
class SessionManager(private val storage: SecureStorage) { fun token(): String? = storage.read("token") }
// iOS entry point that receives the Swift implementation:
fun createSessionManager(storage: SecureStorage): SessionManager = SessionManager(storage)
```
```swift
final class KeychainStorage: KotlinBase, SecureStorage {   // or: KeychainStorage: SwiftBase, SecureStorage
    func read(key: String) -> String? { /* Keychain */ }
    func write(key: String, value: String) { /* Keychain */ }
    func wipe() async throws { /* ... */ }
}
let session = createSessionManager(storage: KeychainStorage())
```
Best for stateful services, several related operations, APIs that the Android side implements the same way
(`expect`-free platform abstraction), and anything with flows. Rules: the Swift class must inherit `KotlinBase` or
an exported Kotlin `open class` (Swift structs/enums can't conform); `suspend` → `async throws`; `Flow<T>` members return `any KotlinTypedFlow<T>`,
obtained from a typed Kotlin builder because Swift can't create flows (`wrapping-generics.md` Pattern 5); keep the
interface non-generic (or give Swift a concrete sub-interface) so signatures are typed.

Pick A for a handful of functions, B for a real service object. Both replace ObjC-era protocol implementations and
SKIE/KMP-NC callback adapters. If the project wires platform services through DI (Koin), register the Swift-provided
instance at startup from an iOS entry point (`fun initKoin(storage: SecureStorage)`), keeping Koin types internal.

## Step 5 — DI / app entry points (common pattern)

```kotlin
// commonMain
internal fun initKoinInternal(appDeclaration: KoinAppDeclaration? = null) = startKoin {
    appDeclaration?.invoke(this); modules(commonModule, platformModule)
}
internal val commonModule = module { singleOf(::RepoImpl) bind Repo::class; viewModelOf(::ItemsViewModel) }

// iosMain — Swift-facing, no Koin types
fun initKoin() { initKoinInternal() }
fun itemsViewModel(): ItemsViewModel = KoinPlatform.getKoin().get()

// androidMain / jvmMain — keep the rich overloads for other platforms
fun initKoin(appDeclaration: KoinAppDeclaration? = null) = initKoinInternal(appDeclaration)
```
Swift: `di.initKoin()`; `let vm = di.itemsViewModel()`. Alternatively an `object KmpProvider { fun repo(): Repo }`
→ `KmpProvider.shared.repo()`.

### Koin compiler plugin → Koin DSL (only with the user's permission, SKILL.md Phase 1 step 3)

Verified on PeopleInSpace (Koin 4.2.2, Kotlin 2.5.0-RC2). One DSL line per annotated class; the module and
the public entry points keep their names, so other modules and Swift don't change.
```kotlin
// Before — annotations processed by io.insert-koin.compiler.plugin
@Single class PeopleInSpaceRepository(api: PeopleInSpaceApi) : PeopleInSpaceRepositoryInterface
@KoinViewModel class PersonListViewModel(repo: PeopleInSpaceRepositoryInterface) : ViewModel()
@Module @ComponentScan("dev.example") class AppModule        // + per-platform @Module classes

// After — plain Koin DSL (imports: org.koin.dsl.module, org.koin.core.module.dsl.{singleOf, viewModelOf, bind})
internal val commonModule = module {                             // internal, not private: other files (initKoin, tests) read it
    single { Json { ignoreUnknownKeys = true } }                 // @Single functions -> single { ... }
    singleOf(::PeopleInSpaceApi)                                 // @Single class -> singleOf(::Class)
    singleOf(::PeopleInSpaceRepository) { bind<PeopleInSpaceRepositoryInterface>() }   // annotations bound supertypes implicitly
    viewModelOf(::PersonListViewModel)                           // @KoinViewModel -> viewModelOf (koin-core-viewmodel)
}
expect fun nativeModule(): Module                                // per-platform @Module -> expect/actual module { ... }

fun initKoin(appDeclaration: KoinAppDeclaration? = null) =      // unchanged signature
    startKoin { includes(appDeclaration); modules(commonModule, nativeModule()) }
```
Then remove the annotations, `koin-annotations`, and the plugin from `plugins {}` (left applied it fails with
`KOIN-D002`). Compile every platform that has a `nativeModule()` actual (JVM, Android, Wasm, iOS). Add a comment
that the rewrite is temporary until a plugin release supports the new Kotlin.

## Step 6 — check after each change

Rebuild (Phase 3 of SKILL.md) and grep the generated `<Module>.swift` for:
- dependency modules you didn't intend to export (`import IoKtor...`, `AppCashSqldelight...`),
- `@available(*, unavailable` stubs ("Declaration uses unsupported types") on things Swift needs,
- `fatalError()` bodies, `Swift.Never` parameters,
- `_KotlinBridgeable` where you expected a concrete type.
