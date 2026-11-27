# Hiding a dependency that breaks Swift Export, and wrapping it in user code

The `export { swift { } }` DSL can **hide** any module in the Swift Export graph (direct or transitive
dependency) with `SwiftExportVisibility.HIDDEN`. A hidden module is translated only as shallow declarations:
member-less stub types for the declarations other modules refer to. It neither breaks the build nor pollutes the
Swift API, so the dependency's own exporter bugs disappear.

**Policy: when the Swift Export build breaks inside a dependency's generated code, hide that dependency and expose
only the wrappers Swift needs from the user's module.** Don't patch generated files, don't post-process generated
Swift in Gradle, and don't wait for a Kotlin fix. Report every hidden dependency and wrapper to the user.

## 1. Recognize a broken dependency

The error points into generated files of a module **other than** the user's exported module:

| Where it fails | Example |
|---|---|
| `compileSwiftExportMainKotlin<Target>` with `e: .../build/SwiftExport/<KOTLIN_TARGET>/files/<DepModule>/<DepModule>.kt:...` | Kotlin bridge of the dependency doesn't compile (type mismatch, unresolved reference, generic it can't express) |
| `<KOTLIN_TARGET><Config>BuildSPMPackage` with Swift errors in `.../Sources/<DepModule>/<DepModule>.swift` | `invalid redeclaration`, `cannot find type`, protocol conformance errors in the dependency's generated Swift |
| Swift Export worker crash/exception while translating, mentioning the library's classes | exporter can't handle a construct of the library |

### Before hiding: export through the umbrella

Big libraries (SQLDelight, Koin, lifecycle, serialization, coroutines) fail mostly when they are **exported in
full**, i.e. direct `api` deps of the module that has `xcodeIntegration()`. Fix that first with the `:ios-export`
umbrella (SKILL.md Phase 2). Known library failures, their exact error texts and the `configure(...)` coordinate
to hide if they still fail: `known-issues.md` ("Swift Export build"). **Never hide kotlinx-coroutines-core**
(every `Flow`/`StateFlow` in your API needs it).

Use the coordinate that appears in the iOS dependency graph (e.g. JetBrains
`org.jetbrains.androidx.lifecycle:lifecycle-viewmodel` resolves to Google's `androidx.lifecycle:lifecycle-viewmodel`
on iOS — the Swift module `AndroidxLifecycleLifecycleViewmodel` is the Google one).
```kotlin
xcodeIntegration {   // in <EXPORT_MODULE> (e.g. :ios-export); keep only the lines for libraries that still fail through the umbrella
    configure("app.cash.sqldelight:runtime", SwiftExportVisibility.HIDDEN)
    configure("androidx.lifecycle:lifecycle-viewmodel", SwiftExportVisibility.HIDDEN)
    configure("io.insert-koin:koin-core", SwiftExportVisibility.HIDDEN)
    configure("org.jetbrains.kotlinx:kotlinx-serialization-core", SwiftExportVisibility.HIDDEN)
}
```
Then make sure Swift never calls a member of these types (they become member-less stubs; see §3).

`<DepModule>` is the Swift module name. Map it back to Gradle coordinates:
- external libraries: `group` + `name` in UpperCamelCase, dots and dashes dropped —
  `IoKtorKtorClientCore` = `io.ktor:ktor-client-core`, `AppCashSqldelightRuntime` = `app.cash.sqldelight:runtime`,
  `OrgJetbrainsKotlinxKotlinxSerializationCore` = `org.jetbrains.kotlinx:kotlinx-serialization-core`;
- project modules without their own `export { swift { moduleName } }`: derived from Gradle coordinates (group
  defaults to the root project name), e.g. `MyAppCoreDb` for `:core:db`;
- confirm with the dependency report: `./gradlew <SHARED_MODULE>:dependencies --configuration iosSimulatorArm64CompileKlibraries`
  (or `...MainImplementationDependenciesMetadata`) and the module list in
  `<EXPORT_DIR>/build/SwiftExport/<KOTLIN_TARGET>/modules.json`.

If the error is in the **user's own** module file (`files/<Module>/<Module>.kt|swift`), it's not a dependency
problem — see `limitations-and-workarounds.md` (e.g. List/Set/Map inheritors as parameters).

## 2. Hide it

```kotlin
import org.jetbrains.kotlin.gradle.swiftexport.ExperimentalSwiftExportDsl
import org.jetbrains.kotlin.gradle.plugin.mpp.export.SwiftExportVisibility

kotlin {
    export {
        @OptIn(ExperimentalSwiftExportDsl::class)
        swift {
            moduleName = "<BASENAME>Export"   // in <EXPORT_MODULE> (has xcodeIntegration()): the umbrella; direct export: "<BASENAME>"
            xcodeIntegration {
                // <Why>: Swift Export generates uncompilable code for this library (<error summary>).
                // Swift uses the wrappers in <ROOT_PKG>.network instead.
                configure(libs.ktor.client.core, SwiftExportVisibility.HIDDEN)
                configure("app.cash.sqldelight:runtime", SwiftExportVisibility.HIDDEN)
                configure(project(":core:db"), SwiftExportVisibility.HIDDEN)
            }
            // If swiftPackageIntegration { } is used too, repeat the same configure(...) calls there.
        }
    }
}
```
- Works for direct and **transitive** dependencies: the selector is matched against resolved components, so a
  transitive library can be hidden without adding it to `dependencies {}`. Use full `group:name` (version ignored),
  a catalog accessor, or `project(...)`. A selector that matches nothing is an error
  (`SwiftExportModuleResolutionError`) — check coordinates against the dependency report.
- Hide the smallest set that fixes the build; rebuild after each one. A failure can move to the next library.
- Don't hide `kotlinx-coroutines-core` (see above). Never hide the user's exported module itself.
- First choice for dependencies Swift doesn't need: declare them `implementation(...)`, not `api(...)` — then only
  the parts reachable from your public API are exported. Hide them if their types still leak.

## 3. What hiding does to the user's API (important)

From the Kotlin test `hiddenFromSwiftExport` (golden output):

```kotlin
// hidden module
class HiddenClass { fun member(): Int }       open class HiddenOpenClass      interface HiddenInterface
// user module
class InheritsHiddenClass : HiddenOpenClass()
fun produce_hidden_class(): HiddenClass
fun consume_hidden_class(arg: HiddenClass)
class Container { val member_property: HiddenClass; fun untouched_member(arg: Int): Int }
```
```swift
// hidden module: stubs only, no members, unreferenced declarations omitted
public final class HiddenClass: KotlinRuntime.KotlinBase { }
open class HiddenOpenClass: KotlinRuntime.KotlinBase { }
public protocol HiddenInterface: KotlinRuntime.KotlinBase { }
// user module
public final class InheritsHiddenClass: ExportedKotlinPackages.hidden.HiddenOpenClass { ... }   // still works
public func produce_hidden_class() -> ExportedKotlinPackages.hidden.HiddenClass { fatalError() }   // !!
public func consume_hidden_class(arg: ExportedKotlinPackages.hidden.HiddenClass) { fatalError() }  // !!
public var member_property: ExportedKotlinPackages.hidden.HiddenClass { get { fatalError() } }      // !!
public func untouched_member(arg: Swift.Int32) -> Swift.Int32 { /* real bridge */ }
```

- Types from the hidden module still exist (so inheritance/conformance and signatures compile), but have
  **no members** — Swift code calling members on them (`koin.get()`) no longer compiles.
- The size win is large: in the swift-export-sample, hiding Koin shrank `IoInsertKoinKoinCore.swift` from 1,818
  lines / 40 types to 23 lines / 2 stubs, and `KotlinStdlib.swift` from 1,729 to 242 lines. Hiding is useful even
  for libraries that export fine but leak by accident.
- **Every user declaration whose signature mentions a hidden type compiles but traps (`fatalError()`) when
  called** — there is no compile-time warning. So hiding alone is not enough if Swift used those APIs.

## 4. Build wrappers in user code

Goal: no Swift-facing (public, exported) declaration in the user's module mentions a type from the hidden module.
Keep the dependency as an implementation detail; expose your own types, primitives, `List`/`Map`, `Flow`/`suspend`.

1. Find affected declarations: run `scripts/find-generated-swift.sh <EXPORT_DIR>` — its last section lists every
   generated declaration whose body is just `fatalError()` (the trapping stubs). Also search the generated
   `<Module>.swift` for the hidden module's namespace (e.g. `ExportedKotlinPackages.io.ktor`,
   `ExportedKotlinPackages.app.cash.sqldelight`), and cross-check which ones Swift code calls.
2. For each, either make it `internal` (if Swift doesn't need it) or replace it with a wrapper:

```kotlin
// BEFORE — leaks Ktor types to Swift; after hiding Ktor these trap at runtime
public class Api(public val client: HttpClient) {
    public suspend fun get(path: String): HttpResponse = client.get(path)
}

// AFTER — library stays internal, Swift sees only own types
public class Api internal constructor(private val client: HttpClient) {
    public suspend fun fetchText(path: String): String = client.get(path).bodyAsText()
    public suspend fun fetchUser(id: String): User = client.get("users/$id").body<UserDto>().toUser()
}
public fun createApi(baseUrl: String): Api = Api(createHttpClient(baseUrl))     // Swift: createApi(baseUrl:)

public data class User(val id: String, val name: String)                        // own model instead of library DTO
```

Common wrapper shapes:

| Library type leaking into Swift | Wrapper |
|---|---|
| client/engine/database objects (`HttpClient`, `SqlDriver`, `Database`) | `internal` field + `internal constructor`; public factory function returning your class |
| library models/DTOs in return types | your own `data class`/`enum class` + mapping function (internal) |
| library enums/sealed results (`Result`, `HttpStatusCode`) | your own sealed class/enum (Swift gets `sealedType()` / native enum) |
| library `Flow<LibType>` / `suspend` returning library types | `Flow<OwnType>` via `.map { it.toOwn() }`, `suspend fun ...: OwnType` |
| library interface Swift must implement (callbacks, loggers, drivers) | declare your own interface in the user module; internal adapter implementing the library interface delegates to it |
| library types as parameters (config builders, `Json`, `Url`) | take primitives / your own config `data class`; build the library object internally |
| library base classes your public classes extend (`ViewModel` from a hidden lib, `KoinComponent`) | don't extend in public API, or expose a public interface + internal implementation |
| platform-specific needs (`initKoin(appDeclaration: KoinAppDeclaration)`) | Unit-returning iOS entry point in `iosMain`; keep rich overloads in `androidMain`/`jvmMain` |

3. If the problem is **generated public code** (SQLDelight `Database`/`*Queries`, Koin annotations) in a separate
   module, declare that module as `implementation` and hide it — no restructuring needed. Only if such code is
   generated into the exported module itself and breaks its export, move it into its own module (then hide it).
4. Rebuild; grep the generated user module again — it must not reference the hidden module's namespace in any
   declaration Swift uses, and must contain no `fatalError()` bodies for them. Then update Swift call sites to the
   wrapper API and run the app to exercise those paths.

## 5. Report

Tell the user: which dependency was hidden and the exact error that caused it, which public Kotlin declarations
became internal or were replaced, the new wrapper API, and that the hidden module's types are member-less stubs in
Swift (any remaining reference traps at runtime). Suggest filing the exporter bug (kotl.in/issue) with the error,
and removing the `HIDDEN` override once fixed.
