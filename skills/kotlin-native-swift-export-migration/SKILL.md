---
name: kotlin-native-swift-export-migration
description: >
  Load when migrating a Kotlin Multiplatform iOS app from the Objective-C
  framework export (SKIE, KMP-NativeCoroutines) to Kotlin Swift Export, moving
  off the deprecated swiftExport {} DSL, or fixing embedSwiftExportForXcode or
  generated-Swift errors after the switch. Not for Kotlin upgrades that stay
  on Objective-C export.
license: Apache-2.0
metadata:
  author: github:@mMaxy
  version: "0.1.0"
  provider: anthropic
  tested_models: "anthropic/claude-haiku-5-5"
  agent_version: "claude-code 2.1.332"
  last_eval: "2026-11-27"
---

# Migrating a KMP project from Objective-C export to Swift Export

> Already on `export { swift {} }` and troubleshooting? Go to Phase 3 triage and `references/known-issues.md`.

Swift Export generates a real Swift API (modules, enums, `async` functions, typed flows, native collections)
from Kotlin instead of an Objective-C header. Migrating = switch Gradle + Xcode, shape the Kotlin public API,
rewrite every Swift call site. This file is the workflow; details live in `references/`.

Swift Export is **Beta**. Docs: kotlinlang.org/docs/native-swift-export.html; the setup page and migration guide
are drafts in kotlin-web-site (branch `swift-export-main`, PR #5954; not on kotlinlang.org yet). Sample:
github.com/Kotlin/swift-export-sample.
For exact API shapes the **generated Swift file** is authoritative — read it instead of guessing (Phase 3).

## Reference files — load as needed

| File | Read it when |
|---|---|
| `<SKILL_DIR>/scripts/preflight.sh <REPO_ROOT>` | Phase 0: prints the variables below, targets, consumers, plugin versions, NOTES, DECISIONS |
| `<SKILL_DIR>/scripts/scan-objc-export-usages.sh <REPO_ROOT> <SHARED_DIR>` | Phase 0: inventory of Gradle/Kotlin/Swift/Xcode code that must change |
| `<SKILL_DIR>/scripts/find-generated-swift.sh <EXPORT_DIR> [symbol]` | Phase 3+: locate/grep the generated Swift; lists `fatalError()` stubs |
| `<SKILL_DIR>/scripts/verify.sh ...` | Phase 6: clean build + log + pbxproj checks, PASS/FAIL per check |
| `references/known-issues.md` | **Any error** — version-specific symptoms with exact error text and fixes |
| `references/gradle-and-xcode.md` | Gradle DSL, multi-module export, Xcode build settings, SwiftPM output, Gradle diagnostics |
| `references/kotlin-to-swift-mapping.md` | What a Kotlin construct becomes in Swift |
| `references/swift-call-site-rewrites.md` | Rewriting Swift code (ObjC-export spelling → Swift Export), incl. SKIE / KMP-NC replacements |
| `references/kotlin-api-preparation.md` | Shrinking/reshaping the exported Kotlin API, removing SKIE/KMP-NC, DI entry points |
| `references/wrapping-generics.md` | Swift-facing API uses generic classes/interfaces/sealed states (`ScreenState<T>`, `Result<T>`) |
| `references/hiding-broken-dependencies.md` | The build fails inside a **dependency's** generated code — hide it and wrap it |
| `references/limitations-and-workarounds.md` | Something is missing from the generated Swift, doesn't compile, or crashes at runtime |

## Variables

Phase 0 records these (Phase 2 the export module); every example below uses them. Don't assume `shared`.

| Variable | Meaning | Example |
|---|---|---|
| `<SKILL_DIR>` | this skill's directory; run its scripts from `<REPO_ROOT>` as `<SKILL_DIR>/scripts/…` | `~/.claude/skills/kotlin-native-swift-export-migration` |
| `<REPO_ROOT>` | root of the Gradle build (where `settings.gradle(.kts)` and `gradlew` are) | `.` |
| `<SHARED_MODULE>` | Gradle path of the Kotlin module that builds the Apple framework today | `:common` |
| `<SHARED_DIR>` | its directory | `common` |
| `<BASENAME>` | the old framework `baseName` = what Swift imports today (`import <BASENAME>`) | `common` |
| `<ROOT_PKG>` | common root package of the Swift-facing Kotlin code | `com.example.app.common` |
| `<APP_TARGETS>` | Xcode targets that link the framework **and** whose platform `<SHARED_MODULE>` builds | `iosApp` |
| `<EXPORT_MODULE>` / `<EXPORT_DIR>` | module with `xcodeIntegration()` and its dir: the umbrella `:ios-export` / `ios-export`, or with direct export `<SHARED_MODULE>` / `<SHARED_DIR>` (Phase 2) | `:ios-export` / `ios-export` |
| `<XCODE_PROJECT>` | the `.xcodeproj` of `<APP_TARGETS>` (preflight `APP_TARGET_n`) | `iosApp/iosApp.xcodeproj` |
| `<SCHEME>` | scheme that builds the app (`APP_TARGET_n` schemes, else `xcodebuild -list -project <XCODE_PROJECT>`) | `iosApp` |
| `<BUNDLE_ID>` | the app target's `PRODUCT_BUNDLE_IDENTIFIER`, Debug value (`APP_TARGET_n`) | `com.example.app` |
| `<SIM_UDID>` | the iPhone simulator to use: the user's, else one from `xcrun simctl list devices available` | `385165F0-…` |
| `<KOTLIN_TARGET>` | Kotlin/Native target, as in `build/SwiftExport/<KOTLIN_TARGET>/` | `iosSimulatorArm64` |
| `<BuildType>` | Swift package build type in task names: `Debug` or `Release` | `Debug` |
| `<SCRATCH>` | a scratch dir outside the repo for logs, derived data, Maestro output | your session scratchpad |

## Hard requirements and ground rules

- **Kotlin 2.5.0 or a 2.5.0 pre-release.** Use the version the user asked for; else the newest stable 2.5.x;
  if none is out, the newest 2.5.0 pre-release (e.g. `2.5.0-RC2`; using it is a Phase 0 decision unless the
  user named a version) — never a dev/snapshot build. Before 2.5.0 only the deprecated `swiftExport { }` DSL exists.
- **Gradle ≥ 8.14**, **AGP ≥ 8.8.2** (if Android is present) — enforced by KGP. macOS host, **Xcode 16+**.
- **Deployment target ≥ iOS 18 / macOS 15 / tvOS 18 / watchOS 11** (generated coroutine support uses
  `Synchronization.Mutex`; KGP fails `embedSwiftExportForXcode` otherwise).
- **Direct integration (Run Script) or Swift package integration.** CocoaPods (`kotlin("native.cocoapods")`) is
  **not supported**. Move such a project off CocoaPods first with the `kotlin-tooling-cocoapods-spm-migration` skill (same repository: https://github.com/Kotlin/kotlin-agent-skills/tree/main/skills/kotlin-tooling-cocoapods-spm-migration): it ends on the direct
  integration (`embedAndSignAppleFrameworkForXcode` Run Script, iOS libraries via `swiftPMDependencies {}`, still
  ObjC export). Build and run the app there, then start this skill at Phase 0. SwiftPM-imported libraries keep
  working: Swift Export exports their cinterop modules.
- **Git:** work on a new branch (or the one the user set up); don't commit unless asked; never push, never
  force-push, never reset or discard work you didn't make (no `git checkout -- .`).
- **Tools:** use the project's/user's version manager (e.g. mise, sdkman); ask before installing anything
  system-wide. Private project: `PREFLIGHT_OFFLINE=1` (online, preflight sends plugin IDs to public repos).

If a requirement can't be met, stop and tell the user — don't half-migrate.

## Workflow

### Phase 0 — Inventory, toolchain probe, one decision point

1. Run `<SKILL_DIR>/scripts/preflight.sh <REPO_ROOT>` (`PREFLIGHT_KOTLIN=<v>` if the user named a Kotlin version).
   Record `<SHARED_MODULE>`, `<SHARED_DIR>`, `<BASENAME>`, `<ROOT_PKG>` (a guess: confirm it covers most
   Swift-facing declarations), `<APP_TARGETS>`, and from `APP_TARGET_n` `<XCODE_PROJECT>`, `<SCHEME>`,
   `<BUNDLE_ID>`; pick `<SCRATCH>` and `<SIM_UDID>`. Note the other lines too (`OUT_OF_SCOPE_TARGETS`,
   `KMPNC_FOR_TARGET`, `API_CONFIGS`, `CONVENTION_PLUGIN_FRAMEWORK` = edit the framework config there,
   `DEPRECATED_SWIFT_EXPORT_DSL` = Phase 2 step 5 is mandatory, ...). `SHARED_MODULE=not found` → find it by hand
   first. `TODO_OFFLINE` → read only the listed public `maven-metadata.xml` files yourself. NOTES are
   informational; `DECISION_n` lines go to step 4. A consumer of a prebuilt or committed framework that nothing
   in this repo produces is out of scope: leave it and mention it.
2. Run `<SKILL_DIR>/scripts/scan-objc-export-usages.sh <REPO_ROOT> <SHARED_DIR>`: ObjC interop, KMP-NC and Koin
   annotations, risky public signatures (mutable collections, `ArrayList`, enums in collections, generics,
   NSObject-named properties), and the ObjC-export idioms used in Swift.
3. **Toolchain probe** (on the branch). First `git status --porcelain`: not clean → stop and ask (stash only with
   permission). Bump Kotlin (catalog entry + every `KOTLIN_VERSION_LITERALS` hit). Remove SKIE (it pins old
   Kotlin). **KMP-NativeCoroutines: don't remove it** — bump it to `KMPNC_FOR_TARGET` (a plain release only if
   its release notes name the target Kotlin; e.g. `1.0.7-kotlin-2.5.0-RC`, verified on 2.5.0-RC2) and switch it
   to its Swift Export compatibility mode, keeping every annotation (`kotlin-api-preparation.md` Step 1); no
   release for the target Kotlin → a step 4 decision. User asked to drop KMP-NC → remove it, R25 cleanup in Phase 5. Compile `./gradlew <SHARED_MODULE>:compileKotlinJvm` (no JVM target:
   `compileAndroidMain` or `compileDebugKotlinAndroid`; see `./gradlew <SHARED_MODULE>:tasks --all`) **and**
   `compileKotlin<AppleSimTarget>`, e.g. `./gradlew <SHARED_MODULE>:compileKotlinIosSimulatorArm64` (Kotlin/Native-only
   breakage shows up only here). For each failure apply Phase 1 steps 1–2; whatever still fails becomes a
   decision. **The probe edits are kept** (Phase 1's starting point). If you stop in step 4, tell the user the iOS
   app won't build until the migration continues, and how to undo the probe: `git stash`, or `git restore <the
   files you changed>` — never `git checkout -- .` (it discards the user's own work).
4. **Ask the user everything at once**, in one message, with the facts for each item:
   - every `DECISION_n` from preflight: deployment target bumps (current → 18.0 / 15.0); **every
     packaging/publishing plugin**, even with no in-repo consumer (they usually publish outside the repo); the
     Kotlin version when it is a pre-release or wasn't checked and the user named none; KMP-NC with no release for
     the target Kotlin (wait, another Kotlin, or drop it); CocoaPods (first the `kotlin-tooling-cocoapods-spm-migration`
     skill, as its own verified step);
   - plugins with no compatible release after Phase 1 steps 1–2: the error, the releases checked, the Phase 1
     step 3 rewrite (or: wait for a release, use a Kotlin it supports);
   - in-repo consumers that will stop building.

   Not questions: plugins behind their latest release (a NOTE; leave them), migrating the deprecated `swiftExport
   { }` DSL. What the user's request already answers ("iOS 18 is fine") is answered. Non-interactive run with
   anything unanswered → **stop here and report** the list. A later phase needing a decision not asked here (e.g.
   Koin's generated `module()` clashing in Phase 3): interactive → ask that one question; else stop and report.

### Phase 1 — Toolchain

Use the project's normal repositories (Maven Central, Google, Gradle Plugin Portal) — no dev, snapshot or local
repos. Upgrade Gradle/AGP if below the requirements. A plugin that breaks on the new Kotlin usually fails with
`NoSuchMethodError` / `NoClassDefFoundError` / `IrGenerationExtensionException` naming `org.jetbrains.kotlin.*`.
Look the symptom up in `known-issues.md`, then fix in this order:

1. **A newer release of the plugin.** Check what is published *now* (quoted versions go stale): the `PLUGIN=`
   lines (or `maven-metadata.xml`) and the GitHub release notes on supported Kotlin (`gh api
   repos/<org>/<repo>/releases --jq '.[0:5][] | .tag_name + " " + .published_at'`). Take the newest that supports
   the target Kotlin (pre-releases count if it is an RC). Some plugins are versioned apart from their library
   (Koin compiler plugin 1.x vs Koin 4.x).
2. **A transitive artifact** in the stack trace (often KSP brought by another plugin): force a newer version of
   it on the buildscript classpath and keep the plugin — at the **top** of the root `build.gradle.kts`, before
   `plugins {}`:
   ```kotlin
   buildscript { configurations.classpath { resolutionStrategy.force("<group>:<artifact>:<newer version>") } }
   ```
   (KSP / kotlin-native-nuget: exact coordinates in `known-issues.md`.)
3. **Only with the user's explicit permission (Phase 0 step 4):** replace a code-generation-only compiler plugin
   with equivalent hand-written code. Known case: the **Koin compiler plugin** → Koin DSL modules with the same
   definitions and scopes, e.g. `singleOf(::Impl) { bind<Iface>() }` (annotations bound interfaces implicitly);
   keep public entry points like `initKoin(...)`; remove the plugin too (else `KOIN-D002`). Worked example:
   `kotlin-api-preparation.md` ("Koin compiler plugin → Koin DSL"). Report it as temporary.
4. Otherwise stop and report. **Never remove a plugin, target, packaging/publishing step or feature that has
   nothing to do with iOS** (Windows/NuGet, web, desktop, server, publishing) to make the build pass. The only
   plugin removed without asking is SKIE (Swift Export replaces it); KMP-NC and packaging/publishing plugins
   change only as answered in Phase 0.

Done when the probe compiles (JVM/Android + `compileKotlinIosSimulatorArm64`) — later failures are then
attributable to Swift Export.

### Phase 2 — Gradle + Xcode switch (details: `references/gradle-and-xcode.md`)

**Pick the layout first and record `<EXPORT_MODULE>` / `<EXPORT_DIR>`** (rule and Gradle check:
`gradle-and-xcode.md` §1 "Umbrella or direct export"; anything unclear → umbrella):
- preflight `SHARED_API_DEPS` lists a library (coroutines, Koin, SQLDelight, ...), or the `API_CONFIGS` check
  shows one or fails → **the umbrella**: `<EXPORT_MODULE>` = `:ios-export`, `<EXPORT_DIR>` = `ios-export` (steps 1–5).
- only own modules / nothing, and the check exits 0 → **direct export**: `<EXPORT_MODULE>` = `<SHARED_MODULE>`,
  `<EXPORT_DIR>` = `<SHARED_DIR>`; put `xcodeIntegration()` into step 2's block, skip step 1.

**Why:** every direct `api` dependency of the module with `xcodeIntegration()` is exported **in full** — slow, and
it breaks for common libraries (`known-issues.md`). A thin umbrella avoids that without touching any deps:

1. New module `ios-export/build.gradle.kts` + `include(":ios-export")` in `settings.gradle.kts`:
   ```kotlin
   import org.jetbrains.kotlin.gradle.swiftexport.ExperimentalSwiftExportDsl

   plugins { alias(libs.plugins.kotlinMultiplatform) }   // same alias <SHARED_MODULE> uses

   kotlin {
       iosArm64()                     // mirror every Apple target <SHARED_MODULE> declares
       iosSimulatorArm64()            // (iosX64, macosArm64, tvos..., as KOTLIN_APPLE_TARGETS lists)
       sourceSets { commonMain.dependencies { api(project("<SHARED_MODULE>")) } }
       export {
           @OptIn(ExperimentalSwiftExportDsl::class)
           swift {
               moduleName = "<BASENAME>Export"   // must differ, ignoring case, from every other exported module
               xcodeIntegration()                // registers :ios-export:embedSwiftExportForXcode
           }
       }
   }
   ```
2. In `<SHARED_DIR>/build.gradle.kts` (or the convention plugin, `CONVENTION_PLUGIN_FRAMEWORK`), replace
   `binaries.framework { baseName = "<BASENAME>" }` with (no `xcodeIntegration()` here unless direct export;
   import `ExperimentalSwiftExportDsl` at the top):
   ```kotlin
   export {
       @OptIn(ExperimentalSwiftExportDsl::class)
       swift {
           moduleName = "<BASENAME>"      // same as the old framework, so `import <BASENAME>` keeps working
           rootPackage = "<ROOT_PKG>"     // its declarations are unqualified in Swift
       }
   }
   ```
   Remove leftover `cocoapods { }`. If a kept packaging plugin (Phase 0) or another consumer still needs the
   framework, keep `binaries.framework` (with its `export(...)`/`transitiveExport`) alongside `export { }`
   (never link both into one Xcode target).
3. Any other own module whose types Swift uses gets the same block with its own `moduleName`/`rootPackage`;
   Swift files using its types must `import` it.
4. Large API or OOM: `kotlin.native.swiftExportWorkerJvmArgs=-Xmx4g` in `gradle.properties` (default `-Xmx1g`).
5. **Deprecated `swiftExport { }` block** (`DEPRECATED_SWIFT_EXPORT_DSL`): always migrate every setting with
   `gradle-and-xcode.md` §1b (`flattenPackage` → `rootPackage`, `export(dep) { }`, `configure { }`), then delete
   it; none may remain in any build file or convention plugin (an error in Kotlin 2.5.20, gone in 2.6.0).

Don't hide dependencies up front — only after a build fails inside one (Phase 3).

**Choose the Xcode integration** from `XCODE_INTEGRATION`: direct Run Script → `xcodeIntegration()` (below);
CocoaPods → the `kotlin-tooling-cocoapods-spm-migration` skill first (Hard requirements); app consumes an XCFramework / Swift package →
`swiftPackageIntegration()` on `<EXPORT_MODULE>` (`gradle-and-xcode.md` §4, no Run Script). Packaging/publishing
plugins (`multiplatform-swiftpackage`, KMMBridge, XCFramework publishing): as the user chose in Phase 0.

**Xcode, direct integration**, for each of `<APP_TARGETS>` (Debug **and** Release; app extensions too). Leave
`OUT_OF_SCOPE_TARGETS` (e.g. a macOS app when Kotlin has no `macos*()` target) untouched; mention them.
- Run Script: `./gradlew <SHARED_MODULE>:embedAndSignAppleFrameworkForXcode` → `./gradlew <EXPORT_MODULE>:embedSwiftExportForXcode`
  (keep the `OVERRIDE_KOTLIN_BUILD_IDE_SUPPORTED` guard; the phase must run before "Compile Sources"). **Change
  only the task name**: keep existing arguments (e.g. `-PXCODE_CONFIGURATION=${CONFIGURATION}`), add no new
  flags (`--no-configure-on-demand`, `--no-configuration-cache`, ...). Xcode runs the script in its own
  environment; a flag that worked in your shell can fail there (`known-issues.md`).
- Deployment target as agreed in Phase 0 (≥ 18.0 / 15.0). `ENABLE_USER_SCRIPT_SANDBOXING = NO` written
  explicitly into every migrated target's Debug and Release configurations — also when the key is absent today
  (`verify.sh` checks every configuration and fails on "not set").
- Remove `-framework <BASENAME>` from `OTHER_LDFLAGS` and the `.../build/xcode-frameworks/...` entry from
  `FRAMEWORK_SEARCH_PATHS`; nothing replaces them (outputs are autolinked from `BUILT_PRODUCTS_DIR`). Add the
  system libraries Kotlin deps need — the ObjC framework linked them, the static library doesn't: **SQLDelight
  native driver → `-lsqlite3`**.
- Remove SKIE-generated/helper Swift files or packages, if any. KMP-NativeCoroutines Swift packages stay (until
  the KMP-NC cleanup), bumped to the plain tag of the Gradle plugin (`1.0.7` for `1.0.7-kotlin-2.5.0-RC`; SPM
  ranges don't select pre-release tags); their `asyncSequence(for:)` call sites stay too (Phase 5).
- `rm -rf <SHARED_DIR>/build/xcode-frameworks`. A stale ObjC framework there makes the build "work" only while
  the old settings stay — `import <BASENAME>` then silently resolves to the old ObjC framework. `No such module
  '<BASENAME>'` after removing them means: Run Script missing in that target, runs after "Compile Sources",
  still calls the old task, or `moduleName` ≠ the import.

Edit `project.pbxproj` with care (all configurations, all `<APP_TARGETS>`). Old-style projects (no
`PBXFileSystemSynchronizedRootGroup`): a **new** Swift file needs `PBXFileReference`, `PBXBuildFile`, group and Sources entries.

### Phase 3 — First build, read the generated Swift, triage

With the direct integration, Swift Export tasks only exist under Xcode's environment — build via xcodebuild
(with the Swift package integration run `./gradlew <EXPORT_MODULE>:exportDebugSwiftPackage` first):

```sh
xcodebuild -project <XCODE_PROJECT> -scheme <SCHEME> -configuration Debug \
  -destination 'platform=iOS Simulator,id=<SIM_UDID>' \
  -derivedDataPath <SCRATCH>/se-dd CODE_SIGNING_ALLOWED=NO build > <SCRATCH>/se-build.log 2>&1; echo "exit=$?"
sed 's/\x1b\[[0-9;]*m//g' <SCRATCH>/se-build.log > <SCRATCH>/se-build.clean.log      # Gradle output has ANSI colors
grep -E '^e: | error: |What went wrong' -A6 <SCRATCH>/se-build.clean.log | grep -v '^ *export ' | head -60
```
A failing `PhaseScriptExecution Run Script` is a Gradle error: read after `* What went wrong:`, don't scroll the
log (thousands of `export` lines). Plain Kotlin errors reproduce faster with
`./gradlew <SHARED_MODULE>:compileKotlinIosSimulatorArm64`. No JDK in the Run Script: export `JAVA_HOME` before
xcodebuild (it inherits it); for the Xcode app tell the user to set `org.gradle.java.home` in `~/.gradle/gradle.properties`.

Then run `<SKILL_DIR>/scripts/find-generated-swift.sh <EXPORT_DIR>` and **read** the shared module's file
`<EXPORT_DIR>/build/SwiftExport/<KOTLIN_TARGET>/files/<BASENAME>/<BASENAME>.swift` (the umbrella's own file is
nearly empty). Every Swift rewrite must match it: names, namespaces (`ExportedKotlinPackages.…` + generated
typealiases), labels, optionality, `any` protocols, `sealedType()`, flows. Library modules (`KotlinStdlib`,
`OrgJetbrainsKotlinxKotlinxCoroutinesCore`) and `KotlinCoroutineSupport.swift` sit next to it.

Triage — first search `known-issues.md` for the exact error text:
- `compileSwiftExportMainKotlin<Target>` fails in `files/<BASENAME>/<BASENAME>.kt` (your module) → a declaration
  uses an unsupported construct (e.g. `MutableList`/`MutableSet`/`MutableMap` parameters → read-only types;
  collections of generic types → `wrapping-generics.md`). Adjust the signature or hide it with `@HiddenFromObjC`.
  Note the error for the report (kotl.in/issue).
- Fails in a **dependency's** generated code (`files/<DepModule>/…` or `Sources/<DepModule>/…`, `<DepModule>` ≠
  yours) → first make sure you export through the umbrella (Phase 2) — big libraries break only when exported in
  full. If it still fails, **hide that dependency and wrap it**: `hiding-broken-dependencies.md` (the only place
  that procedure is described). An error inside `KotlinStdlib` comes from whichever dependency drags that type in.
- `Duplicate Swift Module Names` → two exported modules have the same name ignoring case: rename in its build file.
- `garbage collector is thrashing` / OOM → `kotlin.native.swiftExportWorkerJvmArgs=-Xmx4g`, then shrink the API (Phase 4).
- `<KOTLIN_TARGET>DebugBuildSPMPackage` fails in your own module → reshape the declaration (Phase 4).
- Swift compile errors in the app → expected; Phase 5.

### Phase 4 — Shape the Kotlin API (details: `references/kotlin-api-preparation.md`)

Only for what forces it (build failure in your module's generated code, slow/OOM, a Swift call site needing an
API that exports badly) — other platforms use the same API.
- Swift Export exports **every public declaration** of the exported modules plus what dependencies they reach.
  **Only on a build failure, OOM or a huge surface:** make non-Swift-facing code `internal` (DI, HTTP, DB),
  consider `explicitApi()`, keep library types out of public signatures (internal constructors, Unit-returning
  iOS entry points, interface + factory); internal-only deps are `implementation`. After any visibility change
  build the non-iOS consumers of `<SHARED_MODULE>` right away (Phase 6 step 3 commands).
- Unsupported constructs (table: `kotlin-api-preparation.md` Step 3): default args → overloads; `inline reified`
  → `KClass` variant; `protected` → public accessor; mutable collection params → read-only; throwing non-suspend
  functions → `@Throws`; member **properties** named `description`, `debugDescription`, `hash`, `hashValue`,
  `superclass` are dropped (Swift silently reads NSObject's, KT-90497) → rename or `@ObjCName(swiftName = "description_")`.
- Generic classes/interfaces/sealed states in the Swift-facing API → non-generic wrappers mapped in Kotlin
  (`wrapping-generics.md`).
- Swift-only APIs for Kotlin: closures or a Kotlin interface implemented in Swift (`kotlin-api-preparation.md` Step 4).
- Rename Kotlin types that clash with Swift/SwiftUI (`Shape`, `Color`, `Text`, `Result`, ...).
- **Always, before the first run** (they compile but crash or fail at runtime; the scan lists them):
  - Swift-facing enums inside collections (`List<MyEnum>`, `Map<String, MyEnum>`, `Flow<List<List<MyEnum>>>`) —
    KT-90088, Swift aborts in `KotlinFlowIterator.next()`; give Swift an enum-free shape (`known-issues.md`).
  - public `ArrayList`/`HashMap` types → `List`/`Map` (otherwise an opaque class, and `as! [T]` always fails).
- Remove SKIE-specific Kotlin and ObjC-export hacks (dummy `@Throws` exporters, `@ObjCName` used only to dodge
  mangling — `@ObjCName(swiftName=)` still renames in Swift). KMP-NC annotations stay (compatibility mode).

Iterate Phase 3 ↔ 4 until the Kotlin side and the generated Swift package build.

### Phase 5 — Rewrite Swift call sites (details: `references/swift-call-site-rewrites.md`)

Work file by file, guided by the compiler errors **and** the generated Swift. Most common rewrites:

| ObjC export | Swift Export |
|---|---|
| `import <BASENAME>` (framework) | `import <BASENAME>` (= `moduleName`, case-sensitive); `import <OtherModule>` for other exported modules; `import KotlinRuntime` in files that name `KotlinBase` |
| `Foo` (any package) | `Foo` only if in `rootPackage`; else `subpkg.Foo` / `ExportedKotlinPackages.com.x.subpkg.Foo` |
| `FileNameKt.topLevelFn()` | `topLevelFn()` (root package) or `packageName.topLevelFn()` |
| `MyObject()`, `Foo.companion.x` | `MyObject.shared`, `Foo.Companion.shared.x` |
| `KotlinInt(value: 1)`, `[KotlinInt]`, `KotlinUnit()` | `Int32(1)`/`1`, `[Int32]`, `()` |
| `MyEnum.entryOne`, `.name`, `.ordinal`, `values()` | `MyEnum.ENTRY_ONE` (Kotlin spelling), `.description`, `.rawValue`, `allCases` |
| `data.doCopy(...)`, `doInit`, `doInitKoin()` | `data.copy(...)`, real Kotlin name (`initKoin()`) |
| `onEnum(of: x)` (SKIE) / `as?` chains on sealed types | `switch x.sealedType() { case .a(let t): t.value ... }` |
| `fn(completionHandler:)` | `try await fn()` |
| KMP-NC `asyncFunction(for:)` / `asyncSequence(for: flow)` | **compile unchanged** in compatibility mode (deprecated no-op shims; a deprecation warning on every call is expected, not a failure) — leave them. Element casts (`as! [[T]]`) become "no effect" warnings. KMP-NC Combine/RxSwift helpers (`createPublisher`, `createFuture`, ...) **do** change: R25 |
| SKIE `for await`, collectors | `for try await v in flow.asAsyncSequence()`; StateFlow `.value` |
| Swift class conforming to a Kotlin interface | `import KotlinRuntime` + `final class X: KotlinBase, pkg.Iface` (or inherit an exported Kotlin `open class`); or Swift closures for function-typed params |
| `receiver.extFn()` (extension) | same only for root-package extensions; else `pkg.extFn(receiver)` / `pkg.getProp(receiver)` |
| `catch let e as NSError` | `catch let e as MyKotlinException` (`kotlin.Throwable` is a `Swift.Error`) |

Replace SKIE's `Observing`/`onEnum`/flow bridging with the helpers in `swift-call-site-rewrites.md` (R24–R27).
KMP-NC call sites stay except the Combine/RxSwift helpers (full cleanup R25 only if the user asked to drop it).
Prefer generated package typealiases (`remote.Assignment`); own `typealias`es only to keep a large diff small.

### Phase 6 — Verify

1. `<SKILL_DIR>/scripts/verify.sh --project <XCODE_PROJECT> --scheme <SCHEME> --shared-dir <SHARED_DIR>
   --scratch <SCRATCH> --basename <BASENAME> --targets <APP_TARGETS> --destination 'platform=iOS Simulator,id=<SIM_UDID>'`
   (`--integration spm` for the Swift package integration, after `<EXPORT_MODULE>:export<BuildType>SwiftPackage`).
   Clean Debug simulator build (derived data `<SCRATCH>/verify-dd`) + log + pbxproj checks in every
   configuration + no `swiftExport { }` block left in the repo; prints the built `.app` and bundle id. Every check
   must be `PASS`. `WARN casts-always-fail` lines are real bugs (runtime crashes or dead branches, e.g. a public
   `ArrayList`) — fix them; `INFO casts-no-effect` is expected with KMP-NC compatibility mode.
2. **Run the app** — the `type=application` target (`APP_TARGET_n`) — and exercise every screen that touches
   Kotlin (`<App>` = the `INFO app` path from verify.sh):
   ```sh
   xcrun simctl boot <SIM_UDID> || true
   xcrun simctl install <SIM_UDID> <SCRATCH>/verify-dd/Build/Products/Debug-iphonesimulator/<App>.app
   # capture the app's stdout/stderr for 20 s, then return (`--console-pty` alone never returns;
   # `--stdout=<file>` writes nothing on Xcode 27 simulators)
   perl -e 'alarm 20; exec @ARGV' xcrun simctl launch --console-pty --terminate-running-process <SIM_UDID> <BUNDLE_ID> > <SCRATCH>/app.out 2>&1
   ```
   Read `<SCRATCH>/app.out` for `Fatal error` / uncaught Kotlin exceptions and for the app's own `println` output.
   To keep capturing while Maestro taps, start the same line with a longer alarm in the background
   (`( perl -e 'alarm 120; exec @ARGV' xcrun simctl launch ... > <SCRATCH>/app.out 2>&1 & )`) and use a flow
   without `launchApp`, so the app isn't restarted. You can't tap from the shell — use
   Maestro (through the version manager, e.g. `mise exec maestro@latest -- maestro`). Write a short flow (repo
   flows often need `-e APP_ID=...` and wait on network) and run it in the **foreground** (1–3 min; never in the
   background, don't report before it ends):
   ```yaml
   # <SCRATCH>/se-check.yaml — one tapOn + takeScreenshot per tab/screen that touches Kotlin
   appId: <BUNDLE_ID>
   ---
   - launchApp
   - tapOn: "<second tab label>"
   - takeScreenshot: tab2
   - tapOn: "<first tab label>"
   - tapOn: { id: "<first list row id>" }      # or a visible text
   - takeScreenshot: detail
   ```
   ```sh
   mise exec maestro@latest -- maestro --device <SIM_UDID> test --test-output-dir <SCRATCH>/se-maestro <SCRATCH>/se-check.yaml
   ```
   Read the PNGs under `<SCRATCH>/se-maestro/**/takeScreenshot/`: each screen must show real data. Runtime-only
   leftovers: missing abstract overrides (`fatalError`), `as!` casts that no longer hold, undeclared Kotlin
   exceptions, flows throwing `CancellationError`.
3. Build the other platforms from `OTHER_KOTLIN_TARGETS` and the other in-scope Apple targets — visibility
   changes affect them: e.g. `./gradlew <SHARED_MODULE>:compileKotlinJvm`, `<SHARED_MODULE>:compileAndroidMain`
   or `:<androidApp>:assembleDebug`, `<SHARED_MODULE>:compileKotlinWasmJs`, `:<desktop>:compileKotlin`
   (`./gradlew <module>:tasks --all` for the exact names).
4. Report: what changed and was removed; Kotlin declarations hidden/reshaped and why; dependencies hidden (with
   the error) and their wrappers; Phase 0 decisions and what they changed; out-of-scope targets/consumers;
   features with no Swift Export equivalent; what was verified only by compiling vs. by running (Release, device
   and archive builds are not verified); generated-code failures worth reporting at kotl.in/issue. Leave the
   changes uncommitted unless the user asked for commits.

## Rules of thumb

- The generated Swift beats blog posts, old samples and memory. Search it.
- Never patch or post-process generated files.
- Change the Kotlin API instead of fighting the generated Swift when the API was ObjC-shaped (completion
  handlers, `doInit`, KMP-NC suffixes) — but other platforms use the same API.
- Don't commit generated output; `build/` already holds it.
- macOS tools are BSD: `sed -i '' 's/a/b/' file` (GNU `sed -i` without the `''` fails).
