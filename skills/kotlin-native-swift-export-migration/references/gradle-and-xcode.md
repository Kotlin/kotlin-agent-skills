# Gradle DSL, Xcode integration, SwiftPM output

Applies to Kotlin 2.5.0 and newer (including 2.5.0 pre-releases such as 2.5.0-RC2). Swift Export is Beta.
Official docs: kotlinlang.org/docs/native-swift-export.html. Drafts in kotlin-web-site, not yet on kotlinlang.org:
the setup page `native-swift-export-setup.md` lives on the branch `swift-export-main`; PR #5954 (head
`swift-export-skill` → base `swift-export-main`) changes `native-swift-export-migration-guide.md`,
`native-swift-export.md` and `kr.tree`.
Paths are KGP sources under
`libraries/tools/kotlin-gradle-plugin/src/common/kotlin/org/jetbrains/kotlin/gradle/`.

## 1. From ObjC export to `export { swift { } }`

### Before (typical ObjC export setups)

```kotlin
// A) direct integration
kotlin {
    listOf(iosX64(), iosArm64(), iosSimulatorArm64()).forEach {
        it.binaries.framework {
            baseName = "<BASENAME>"
            isStatic = true
            export(project(":models"))          // re-export a dependency to ObjC
            export(libs.kotlinx.datetime)
        }
    }
}
// B) CocoaPods
plugins { kotlin("native.cocoapods") }
kotlin { cocoapods { summary = "..."; ios.deploymentTarget = "15.0"; framework { baseName = "<BASENAME>" } } }
// plus often: id("co.touchlab.skie"), id("com.rickclephas.kmp.nativecoroutines"), com.google.devtools.ksp,
// io.github.luca992.multiplatform-swiftpackage / co.touchlab.kmmbridge for XCFramework/SPM distribution
```

### After

Recommended layout: a thin `:ios-export` umbrella module with `xcodeIntegration()` and `api(project("<SHARED_MODULE>"))`,
plus `moduleName`/`rootPackage` in `<SHARED_MODULE>` — see SKILL.md Phase 2 (it avoids full export of library `api`
deps). `<EXPORT_MODULE>` / `<EXPORT_DIR>` below mean the module with `xcodeIntegration()` (or
`swiftPackageIntegration()`): `:ios-export` / `ios-export`, or `<SHARED_MODULE>` / `<SHARED_DIR>` in the
single-module form (only when "Umbrella or direct export" below says direct):

```kotlin
import org.jetbrains.kotlin.gradle.swiftexport.ExperimentalSwiftExportDsl
import org.jetbrains.kotlin.gradle.plugin.mpp.export.SwiftExportVisibility   // only if you use visibility

kotlin {
    iosArm64()
    iosSimulatorArm64()

    export {
        @OptIn(ExperimentalSwiftExportDsl::class)
        swift {
            moduleName = "<BASENAME>"           // keeps the old framework name for THIS module only
            rootPackage = "<ROOT_PKG>"          // removes the package prefix in Swift
            xcodeIntegration {                  // enables the direct Xcode integration
                // external library: name it here (you can't edit its build file)
                configure(libs.kotlinx.datetime) { moduleName = "KotlinDateTime"; rootPackage = "kotlinx.datetime" }
            }
        }
    }

    sourceSets {
        commonMain.dependencies {
            api(project(":models"))          // direct `api` deps are fully exported
            implementation(libs.kotlinx.datetime)   // exported only as far as the public API uses it
        }
    }
}

// models/build.gradle.kts — every exported project names its own Swift module (preferred over configure()):
kotlin {
    export {
        @OptIn(ExperimentalSwiftExportDsl::class)
        swift { moduleName = "Models"; rootPackage = "com.example.models" }
    }
}
```

- Opt-in: `@OptIn(org.jetbrains.kotlin.gradle.swiftexport.ExperimentalSwiftExportDsl::class)` on `swift {`, as in
  the official docs (warning-level; can also be `@file:OptIn(...)`).
- Each exported Gradle project is its own Swift module. `moduleName` = old `baseName` keeps `import <BASENAME>`
  working only for that module's declarations; Swift files using other exported modules' types need `import <Module>`.
- `kotlin { export { } }` is a Gradle extension (`kotlin.extensions["export"]`), accessed through generated
  accessors in `build.gradle.kts`. In a precompiled convention plugin without accessors use
  `the<KotlinMultiplatformExtension>().extensions.getByType<org.jetbrains.kotlin.gradle.plugin.mpp.export.ExportExtension>()`.
- `binaries.framework {}` is **not needed** for Swift Export; it builds its own static library on a dedicated
  compilation, named after the `moduleName` of `<EXPORT_MODULE>` in UpperCamelCase (`libShared.a` for
  `moduleName = "shared"`, `libCommonExport.a` for `"commonExport"`). `baseName`/`isStatic`/`export()`/`transitiveExport`/
  `linkerOpts` of the framework have no effect on Swift Export. Delete the framework block if no other
  consumer needs it (another Xcode target still on ObjC export, or a packaging/publishing plugin the user chose to
  keep); otherwise keep it next to `export { }` — but never link both into one Xcode target.
- `-Xexport-kdoc` is not needed — KDoc is exported as `///` DocC comments by default.

### Umbrella or direct export

KGP exports **in full** every direct dependency of the exporting compilation's `api` configuration — the `api`
deps of **every source set that reaches the Apple target** (`commonMain`, `nativeMain`, `appleMain`, `iosMain`,
custom intermediate ones such as `nonWindowsMain`, the target's own `iosArm64Main`), including those a plugin adds
(`internal/SwiftExportedModule.kt`). Decide in this order; anything unclear → umbrella (the safe default):
1. preflight `SHARED_API_DEPS` lists a library (anything but `project(...)` / `projects.x`) → **umbrella**.
2. Otherwise check each configuration of preflight `API_CONFIGS` (it lists the source sets above that exist in
   the build file; plugins can add more):
   ```sh
   for c in <API_CONFIGS, space-separated>; do
     ./gradlew -q <SHARED_MODULE>:dependencies --configuration "$c" --no-configuration-cache || echo "FAILED $c"
   done > <SCRATCH>/api-deps.txt 2>&1
   grep -E -- '--- |FAILED' <SCRATCH>/api-deps.txt | grep -v -- '--- project '
   ```
   No output (every configuration printed `No dependencies` or only `project :x`) → **direct export**. Any
   library line, any `FAILED` (Gradle exit code ≠ 0, e.g. a configuration that doesn't exist) → **umbrella**.
   Don't run `dependencies` without `--configuration`: it resolves every configuration and fails on unrelated
   ones (e.g. a missing JDK toolchain of a desktop/server target).

### 1b. From the deprecated `swiftExport { }` DSL (mandatory when preflight prints `DEPRECATED_SWIFT_EXPORT_DSL`)

Why: KGP 2.5.0 warns `DeprecatedSwiftExportDsl` ("will become an error in Kotlin 2.5.20 and will be removed in
Kotlin 2.6.0", kotl.in/swift-export-dsl-migration); both DSLs together are the ERROR `ConflictingSwiftExportDsls`.
After the migration no `swiftExport { }` block may remain anywhere (module build files, `buildSrc`, `build-logic`
convention plugins) — `verify.sh` fails on one. Map it, then **delete the old block**:

| Old `swiftExport { }` (KGP `SwiftExportExtension`) | New `export { @OptIn(ExperimentalSwiftExportDsl::class) swift { } }` |
|---|---|
| `moduleName = "X"` | `moduleName = "X"` (keeps `import X` working) |
| `flattenPackage = "p"` | `rootPackage = "p"` |
| (the Xcode task was always registered) | `xcodeIntegration()` on `<EXPORT_MODULE>` — the module whose `embedSwiftExportForXcode` the Run Script calls; with the umbrella change that one task path to `:ios-export:embedSwiftExportForXcode` |
| `export(project(":x")) { moduleName = "M"; flattenPackage = "q" }` | in `:x`'s own build file: `export { swift { moduleName = "M"; rootPackage = "q" } }` (no `xcodeIntegration()` there). It is exported in full if it is an `api` dep of `<EXPORT_MODULE>`; if it is `implementation`, add `xcodeIntegration { configure(project(":x"), SwiftExportVisibility.EXPOSED) }` |
| `export(libs.foo) { moduleName = "M"; flattenPackage = "q" }` (a library) | `xcodeIntegration { configure(libs.foo) { moduleName = "M"; rootPackage = "q"; visibility = SwiftExportVisibility.EXPOSED } }` — `EXPOSED` only if Swift needs its whole API (old `export()` meant a full export); else just the names |
| `configure { settings.put(k, v) }` | `xcodeIntegration { settings.put(k, v) }` |
| `configure { freeCompilerArgs.add(...) }` | module-level `compilerOptions { }` (the new DSL has no compiler-argument API) |
| `linkTask { }` | no equivalent; system libraries go into Xcode `OTHER_LDFLAGS` |

Watch out: the legacy DSL exported in full only what `export(...)` listed; the new one exports **every direct
`api` dependency** in full ("Umbrella or direct export" above) — a project that built fine on the old DSL can break
or slow down until it uses the umbrella. Also, `embedSwiftExportForXcode` stays registered even with **no**
`export { swift { } }` block (kept for the legacy DSL until Kotlin 2.6.0, `SetupSwiftExportDSL.kt`), so "the task
runs" does not prove the new DSL is configured: check the build files (`grep -rn 'swiftExport *{'` must find
nothing; `export {` with `xcodeIntegration()` must exist in `<EXPORT_MODULE>`).
- No `freeCompilerArgs`, `linkTask {}`, or `export(dep)` exist in the new DSL. Put compiler flags in the normal
  module-level `compilerOptions {}`. If exported declarations use opt-in APIs (e.g. kotlinx-datetime), add the
  opt-in there in the exporting module: `compilerOptions { optIn.add("kotlin.time.ExperimentalTime") }`.

## 2. DSL reference (`plugin/mpp/export/ExportExtension.kt`)

```kotlin
export {
  swift {
    moduleName = "<BASENAME>"                 // Property<String>; must match ^[A-Za-z0-9_]+$. Always set it: the default
                                              // is derived from the project / Gradle coordinates
    rootPackage = "<ROOT_PKG>"                // Property<String>; unset by default

    xcodeIntegration()                        // activates the Run Script integration (embedSwiftExportForXcode)
    xcodeIntegration {                        // same, with options (repeated calls configure one object)
      settings.put("key", "value")            // raw settings passthrough (currently no documented keys)
      configure(dependency) {                 // override options of a dependency already in the graph
        moduleName = "Utils"
        rootPackage = "com.example.utils"
        visibility = SwiftExportVisibility.EXPOSED   // or HIDDEN
      }
      configure(dependency, SwiftExportVisibility.HIDDEN)   // shorthand
    }

    swiftPackageIntegration()                 // activates SwiftPM package output (export<BuildType>SwiftPackage)
    swiftPackageIntegration {
      outputDirectory = layout.projectDirectory.dir("SwiftPackage")   // default <projectDir>/SwiftPackage
      configure(dependency) { ... }           // separate overrides: repeat them here if you use both integrations
    }
  }
}
```

- `dependency` accepts anything `dependencies {}` accepts: `project(":x")`, `projects.x`, `"group:name:version"`
  (version ignored), `libs.foo`, a `Provider`. Coordinates without a group are rejected. `configure` does **not**
  add a dependency; an override that matches nothing is an error.
- `configure(...)` exists only inside `xcodeIntegration {}` / `swiftPackageIntegration {}` — not directly in
  `swift {}`.
- `rootPackage`: declarations of exactly that package get root-level aliases in the Swift module
  (`public typealias Foo = ExportedKotlinPackages.com.example.shared.Foo`, root-level funcs/vars, and Swift
  `extension`s for its extension functions). Sub-packages become namespaces: `com.example.shared.remote.Assignment`
  → `remote.Assignment` (also via a generated `public typealias remote = ExportedKotlinPackages.com.example.shared.remote`).
  Pick the deepest package that contains most Swift-facing declarations.

### Dependencies and visibility

- Direct `api(...)` dependencies of the exported module: **fully exported** (whole public API, own Swift module).
- Everything else (direct `implementation`, transitive deps, stdlib): **transitively exported** — only the
  declarations reachable from exported API, in their own Swift modules.
- `SwiftExportVisibility.EXPOSED`: force a full export (e.g. an `implementation` dep). `HIDDEN`: the module is
  translated only as shallow declarations — member-less stub types that other modules refer to — so it neither
  breaks the build nor pollutes the Swift API. Works for direct **and transitive** dependencies. Use it for
  internal dependencies whose types leak into the public API and, above all, **to hide a dependency whose
  generated code breaks the build**. User declarations that mention hidden types compile but fail with a fatal
  error at runtime, so expose wrappers for the ones Swift needs: `hiding-broken-dependencies.md`.
- Naming: **set `moduleName`/`rootPackage` in each exported project's own `export { swift { } }` block** (no
  `xcodeIntegration()` there; only the umbrella module calls it). This is the recommended place; the setting is
  published with the library and consumers pick it up automatically. Use the consumer's `configure(...)` only for
  dependencies you don't own or to change visibility.
- Precedence: consumer `configure(...)` (local build only, never published) > the dependency's own
  `export { swift { moduleName; rootPackage } }` > default derived from the dependency's coordinates.
- Default (unconfigured) dependency module names are derived from Gradle coordinates and are long, e.g.
  `org.jetbrains.kotlinx:kotlinx-coroutines-core` → `OrgJetbrainsKotlinxKotlinxCoroutinesCore`. Check
  `<EXPORT_DIR>/build/SwiftExport/<KOTLIN_TARGET>/modules.json` or the generated files for the actual names.
  Two modules mapping to the same name (case-insensitively) is FATAL — rename one with `configure { moduleName }`.
- Hand-written cinterop klibs are not exported; API exposing their types won't be available in Swift.
- Compared to ObjC export: you don't list deps with `export(...)`; *all* public API of the module and its `api`
  deps is exported (ObjC export didn't prune exported public API either). Use `internal`, `implementation`, or
  `HIDDEN` to shrink.

## 3. Xcode integration (Run Script)

```sh
if [ "YES" = "$OVERRIDE_KOTLIN_BUILD_IDE_SUPPORTED" ]; then
  echo "Skipping Gradle build task invocation due to OVERRIDE_KOTLIN_BUILD_IDE_SUPPORTED environment variable set to \"YES\""
  exit 0
fi
cd "$SRCROOT/.."
./gradlew <EXPORT_MODULE>:embedSwiftExportForXcode       # e.g. :ios-export; keep any arguments the old line had
```

- Replaces `embedAndSign<...>AppleFrameworkForXcode` (or the CocoaPods `[CP-User] Build <BASENAME>` phase /
  `syncFramework`). Must run before "Compile Sources" of the target.
- Requires `xcodeIntegration()` in the DSL; run outside Xcode it fails with "Please run the
  embedSwiftExportForXcode task from Xcode ('SDK_NAME', 'CONFIGURATION', ... not provided)".
  The per-target Swift Export tasks (`<KOTLIN_TARGET>SwiftExport`, `compileSwiftExportMainKotlin<Target>`, ...) are
  only registered when Xcode environment variables are present — build via Xcode/xcodebuild to run them.
- Reads `CONFIGURATION` (custom configuration names: set `KOTLIN_FRAMEWORK_BUILD_TYPE=debug|release`),
  `SDK_NAME`, `ARCHS`, `BUILT_PRODUCTS_DIR`, `TARGET_BUILD_DIR`, deployment target setting.
  `ARCHS`/SDK must match declared Kotlin targets (`iosSimulatorArm64` for Apple-silicon simulators, `iosX64`
  for Intel simulators, `iosArm64` for devices).
- Output copied into `BUILT_PRODUCTS_DIR`: the static library (`libShared.a`, see §1), `<Module>.swiftmodule`, one `.swiftmodule` per
  exported dependency, `ExportedKotlinPackages`, `KotlinRuntime`, `KotlinRuntimeSupport`,
  `KotlinCoroutineSupport`, bridge headers. Linked via Swift autolinking.

Build settings for every target that consumed the framework (Debug **and** Release):

| Setting | Value |
|---|---|
| `IPHONEOS_DEPLOYMENT_TARGET` | ≥ `18.0` (macOS ≥ 15.0, tvOS ≥ 18.0, watchOS ≥ 11.0); also bump `platforms` in local `Package.swift` files |
| `ENABLE_USER_SCRIPT_SANDBOXING` | `NO` |
| `OTHER_LDFLAGS` | remove `-framework <baseName>`; add the system libs Kotlin deps need — the ObjC framework linked them, the static library doesn't: `-lsqlite3` whenever SQLDelight's native driver is used |
| `FRAMEWORK_SEARCH_PATHS` | remove `$(SRCROOT)/../<SHARED_DIR>/build/xcode-frameworks/$(CONFIGURATION)/$(SDK_NAME)` |
| `SWIFT_INCLUDE_PATHS`, `LIBRARY_SEARCH_PATHS` | nothing needed |

Swift `import`s:
- `import <BASENAME>` (= `moduleName`, case-sensitive) for `<SHARED_MODULE>`'s declarations; `import <Module>` of each
  other exported Gradle module whose declarations the file uses (e.g. `import Models`).
- `KotlinCoroutineSupport` and `ExportedKotlinPackages` are re-exported (`@_exported import` at the top of the
  generated `<Module>.swift`) — don't import them. `KotlinRuntime` may not be (`known-issues.md`): add
  `import KotlinRuntime` to files that name `KotlinBase`. Check the first lines of the generated `<Module>.swift`
  to see which modules are `@_exported`. With the `MemberImportVisibility` upcoming feature, also import every
  module the compiler asks for (`KotlinStdlib`, dependency modules).
- Swift 6 language mode: `@preconcurrency import <BASENAME>` avoids Sendable diagnostics on Kotlin types.

Local Swift packages (in the app repo) that `import` Swift Export modules: Xcode may compile them before the
Run Script phase. Run Gradle as a **scheme Pre-Action** too (Edit Scheme ▸ Build ▸ Pre-actions ▸ New Run Script
Action, and set **"Provide build settings from: <app target>"** — without it `$SRCROOT`, `SDK_NAME`, `ARCHS`,
`CONFIGURATION` are empty and the task fails), and filter excluded archs there (pre-actions don't apply
`EXCLUDED_ARCHS`):
```sh
cd "$SRCROOT/.."
for arch in $EXCLUDED_ARCHS; do ARCHS="${ARCHS//$arch/}"; done
export ARCHS="$(echo $ARCHS | xargs)"
./gradlew <EXPORT_MODULE>:embedSwiftExportForXcode
```
In the `.xcscheme` file that setting is the `<EnvironmentBuildable>` `BuildableReference` of the app target
inside the pre-action's `<ActionContent>`.

## 4. Swift package integration (replaces XCFramework / KMMBridge / multiplatform-swiftpackage distribution)

Use it when the app consumed an XCFramework / Swift package. (A CocoaPods project first goes through the
`kotlin-tooling-cocoapods-spm-migration` skill, which leaves it on the direct integration: use `xcodeIntegration()`.) An XCFramework project can switch in one step (the built-in package generation replaces the
custom packaging).

`swiftPackageIntegration()` goes on **`<EXPORT_MODULE>`** — the same module that would otherwise call
`xcodeIntegration()`: the umbrella `:ios-export` (recommended, SKILL.md Phase 2), or `<SHARED_MODULE>` with
direct export. `<SHARED_MODULE>` keeps only its `moduleName`/`rootPackage` block.
```kotlin
// ios-export/build.gradle.kts (umbrella; same module as in SKILL.md Phase 2 step 1)
export {
    @OptIn(ExperimentalSwiftExportDsl::class)
    swift {
        moduleName = "<BASENAME>Export"
        swiftPackageIntegration {
            outputDirectory = layout.projectDirectory.dir("SwiftPackage")   // optional; this is the default
            // configure(dep) { ... } — repeat the xcodeIntegration overrides here if you use both
        }
    }
}
```

`swiftPackageIntegration()` registers, per build type: `generate<BuildType>SwiftPackage`,
`assemble<BuildType>SwiftPackageBinary` (`<Module>Kotlin.xcframework`), `export<BuildType>SwiftPackage`
(writes `outputDirectory/<Debug|Release>`). No Xcode environment needed (run on macOS with Xcode installed):

```sh
./gradlew <EXPORT_MODULE>:exportDebugSwiftPackage     # or exportReleaseSwiftPackage; e.g. :ios-export:exportDebugSwiftPackage
```

The package and its product are named after the `moduleName` of `<EXPORT_MODULE>`: package `<moduleName>`,
product `<moduleName>Library` ("the configured moduleName followed by Library"). With the umbrella that is
package `<BASENAME>Export`, product `<BASENAME>ExportLibrary`, in `ios-export/SwiftPackage/<Debug|Release>`; with
direct export package `<BASENAME>`, product `<BASENAME>Library`, in `<SHARED_DIR>/SwiftPackage/<Debug|Release>`.

Xcode steps:
1. Remove the Run Script phase (`embedAndSign...`/`embedSwiftExportForXcode`) and the pod / XCFramework dependency.
2. File ▸ Add Package Dependencies ▸ Add Local… ▸ select the build-type subdirectory (`<EXPORT_DIR>/SwiftPackage/Debug`
   or `.../Release`, **not** `SwiftPackage` itself). Link the `<moduleName>Library` product to the app target;
   Swift still writes `import <BASENAME>` (the shared module's `moduleName`). Or, in an existing `Package.swift`:
   ```swift
   // umbrella shown; direct export: name "<BASENAME>", path "../<SHARED_DIR>/SwiftPackage/Release", product "<BASENAME>Library"
   dependencies: [.package(name: "<BASENAME>Export", path: "../ios-export/SwiftPackage/Release")],
   targets: [.target(name: "App", dependencies: [.product(name: "<BASENAME>ExportLibrary", package: "<BASENAME>Export")])]
   ```
3. Apply the deployment target and `OTHER_LDFLAGS` changes from §3 (build settings table).
4. Remove the SKIE Swift packages. Keep the KMP-NativeCoroutines ones (plain version, SKILL.md Phase 2) until the
   optional KMP-NC cleanup has removed every use.

Rules: re-run the export task after every Kotlin change (and before verifying). Switching Xcode's build
configuration does **not** switch the package directory (a `Debug` dependency always uses the Debug binary).
The export deletes unknown files in the build-type subdirectory — keep nothing of your own there and exclude it
from version control. Apple targets may differ in their dependencies: a module only some targets have gets a
`.when(platforms:)` condition in the generated `Package.swift`. Known issues: `swiftPMDependencies`
imports are not supported; if SwiftUI previews crash, try Editor ▸ Canvas ▸ Use Legacy Previews Execution or a
dynamic package product (KT-91412, `known-issues.md`).

## 5. Gradle properties

| Property | Effect |
|---|---|
| `kotlin.swift-export.experimental.nowarn=true` | silence the "Swift Export is experimental" warning |
| `kotlin.native.swiftExportWorkerJvmArgs=-Xmx4g` | JVM args of the Swift Export worker (whitespace-separated; `-Xmx1g` is added unless you give an `-Xmx`); raise for large APIs / OOM. (`kotlin.swift-export.jvmArgs` does not exist.) |

Remove leftovers: `kotlin.native.cocoapods.*`, SKIE properties, `SWIFT_EXPORT_COROUTINES_SUPPORT_TURNED_ON`
settings (coroutine support turns on automatically when kotlinx-coroutines is in the graph),
`kotlin.mpp.androidSourceSetLayoutVersion` (deprecated).

## 6. Diagnostics and fixes

| Message / ID | Fix |
|---|---|
| `Task 'embedSwiftExportForXcode' not found` | add `xcodeIntegration()` in `export { swift { } }` of that module (the task exists without it only while no `export { swift { } }` block is present: legacy behaviour until 2.6.0) |
| `ConflictingSwiftExportDsls` (ERROR) | remove the old `swiftExport { }` block |
| `DeprecatedSwiftExportDsl` (WARNING in 2.5.0; error in 2.5.20, removed in 2.6.0) | old `swiftExport {}`: migrate it and delete it — §1b |
| `SwiftExportMinimumDeployTargetError`: "Swift Export needs IPHONEOS_DEPLOYMENT_TARGET to be 18.0 or newer" | raise the deployment target of the Xcode target |
| `XcodeUserScriptSandboxingDiagnostic` | `ENABLE_USER_SCRIPT_SANDBOXING = NO` |
| `SwiftExportInvalidModuleName` | only `[A-Za-z0-9_]` in `moduleName` |
| `SwiftExportModuleResolutionError` "... specified in export { swift { xcodeIntegration { configure() } } } were not found" | the dep isn't in the graph — add it to `dependencies {}`; check coordinates |
| `SwiftExportDuplicateModuleNames` (FATAL) / two exported modules resolve to the same Swift module name | `configure(dep) { moduleName = "..." }` or rename the root module |
| `SwiftExportWithoutAppleTargets` | declare Apple targets |
| "Please run the embedSwiftExportForXcode task from Xcode" | run through Xcode/xcodebuild |
| `validateXcodeArchitectures` failure | add the Kotlin target for the Xcode SDK/arch (`iosSimulatorArm64()`, `iosX64()`, `iosArm64()`) |
| Unknown configuration name warning | `KOTLIN_FRAMEWORK_BUILD_TYPE=debug` (or release) in Xcode build settings |
| `e:` errors in `compileSwiftExportMainKotlin<Target>` pointing into `build/SwiftExport/**/<Module>.kt` (your module) | a declaration uses an unsupported construct — adjust the Kotlin signature or hide the declaration; see `limitations-and-workarounds.md` (e.g. mutable collection parameters). Worth filing at kotl.in/issue |
| `e:` errors in `compileSwiftExportMainKotlin<Target>` pointing into `build/SwiftExport/**/files/<DepModule>/<DepModule>.kt` (a dependency) | export through the `:ios-export` umbrella (SKILL.md Phase 2) first; still failing → `hiding-broken-dependencies.md` |
| Declaration missing from the generated Swift or marked unavailable | check the Kotlin signature against the limitations (`limitations-and-workarounds.md`) and adjust it |
| A user-module function fails at runtime with a fatal error | it mentions a type of a hidden dependency — replace with a wrapper that doesn't expose that type |
| Swift errors in `<KOTLIN_TARGET><Config>BuildSPMPackage` (`invalid redeclaration`, type not found) | in a dependency's `<DepModule>.swift`: as the row above; in the user's module: reshape/hide the offending declaration. Exact texts: `known-issues.md` |
| Out of memory in the Swift Export worker (`garbage collector is thrashing`, `OutOfMemoryError`) | `kotlin.native.swiftExportWorkerJvmArgs=-Xmx4g` in `gradle.properties`, then shrink the API |
| KSP/compiler-plugin `NoSuchMethodError` after the Kotlin bump | SKILL.md Phase 1 (newer release, then force the transitive artifact); exact cases in `known-issues.md` |

## 7. Pipeline (for reading logs)

`<KOTLIN_TARGET>SwiftExport` (generates Swift + Kotlin bridges) → `compileSwiftExportMainKotlin<Target>` (compiles
bridges) → `linkSwiftExportBinaryDebugStatic<Target>` → `<KOTLIN_TARGET>DebugGenerateSPMPackage` →
`<KOTLIN_TARGET>DebugBuildSPMPackage` (xcodebuild of a synthetic package compiling the generated Swift) →
`merge<Platform>DebugSwiftExportLibraries` → `copyDebugSPMIntermediates` → `embedSwiftExportForXcode`.
Generated sources (under `<EXPORT_DIR>`): `build/SwiftExport/<KOTLIN_TARGET>/files/<Module>/<Module>.{swift,kt,h}`
and `build/SPMPackage/<KOTLIN_TARGET>/<Config>/Sources/<Module>/` (`<KOTLIN_TARGET>` e.g. `iosSimulatorArm64`;
`<Target>` in task names is the same, capitalized).
