---
name: kotlin-tooling-android-to-multiplatform
description: >
  Migrates pure Android apps to Kotlin Multiplatform (KMP). Handles converting
  Android modules to multiplatform, setting up shared code with expect/actual,
  migrating Compose UI to Compose Multiplatform, and adding iOS entry points
  (with optional Desktop/Web support). Use when the user wants to make an Android app cross-platform, share
  Android code with iOS, migrate to KMP, add iOS support to an Android project,
  or mentions "android to multiplatform", "share code between android and iOS",
  "kotlin multiplatform migration", or "make app cross-platform".
license: Apache-2.0
metadata:
  author: JetBrains
  version: "1.0.0"
---

# Android to Kotlin Multiplatform Migration

This skill guides you through migrating a pure Android app to Kotlin Multiplatform (KMP), 
following the approach demonstrated in the official [JetBrains Jetcaster migration guide](https://kotlinlang.org/docs/multiplatform/migrate-from-android.html).

The migration is incremental — the Android app stays in a working state after every step.
Each module migrates independently, and UI moves screen by screen.

## Before You Start: Safety Principles

Migration is only safe when certain preconditions are met. If they aren't, your job is to
**tell the user what needs to happen first** rather than attempting changes that could break
the project.

**Stop and create a migration plan instead of proceeding if:**
- The project has Java code in modules you'd need to share
- The project uses Android Views instead of Jetpack Compose for UI
- Core dependencies have no KMP alternatives and no clear migration path
- The module structure is deeply tangled (high coupling between modules)
- The project uses build features that KMP doesn't support

In these cases, outline the prerequisite work as a plan with clear steps. The user can
then tackle each prerequisite separately (possibly with dedicated skills for specific
library migrations) before returning to this migration.

## Step 0: Assess the Project

Before making any changes, understand the project structure and readiness.

1. Read `settings.gradle.kts` (or `.gradle`) to find all modules
2. For each module, read `build.gradle.kts` to identify plugins and dependencies
3. Check `gradle/libs.versions.toml` (if it exists) for current library versions
4. Read `gradle.properties` for any relevant flags

If Bash is available, run `scripts/analyze-readiness.sh` from this skill's directory to
get a structured readiness report.

### Evaluate Readiness

Check these prerequisites — they determine whether you can proceed directly or need to
create a plan first:

| Prerequisite       | Ready                                 | Needs Work                                                                    |
|--------------------|---------------------------------------|-------------------------------------------------------------------------------|
| **AGP version**    | AGP 9.0+ with built-in Kotlin support | Older AGP → recommend upgrading first (`kotlin-tooling-agp9-migration` skill) |
| **Language**       | All Kotlin                            | Has Java files in modules to share → convert first                            |
| **UI framework**   | Jetpack Compose                       | Android Views → migrate to Compose first                                      |
| **Async patterns** | Coroutines + Flow                     | RxJava → migrate to coroutines first                                          |
| **Modularization** | Clean module boundaries               | Monolithic app module → modularize first                                      |
| **Dependencies**   | Most have KMP alternatives            | Many Android-only deps → audit and plan replacements                          |

### Classify Each Module

Build a dependency graph of the project's modules. For each module, determine:

- **Can share**: Pure Kotlin business logic, data layer, domain layer — these become KMP modules
- **Must stay Android**: Contains Android-specific entry points (Activity, Application class, AndroidManifest), deep platform integration (NDK, hardware APIs) — stays as Android module
- **UI modules**: If using Compose, can migrate to Compose Multiplatform. If using Views, must stay Android or be rewritten

### Dependency Audit

See [references/DEPENDENCY-MAPPING.md](references/DEPENDENCY-MAPPING.md) for a table of common
Android libraries and their KMP alternatives.

**Important:** Don't attempt to swap libraries as part of this migration. Library migrations can be complex and have their own edge cases. Instead:

1. Identify which dependencies in shared modules lack KMP support
2. Report them to the user with suggested alternatives
3. Recommend migrating those dependencies first, as separate tasks
4. Return to the KMP migration once dependencies are ready

### Determine Migration Order

Start with modules that have the **fewest dependencies on other modules** (leaf modules)
and work your way up the dependency tree. A typical order:

1. `:core:model` or `:core:common` — shared data models
2. `:core:data` — data layer (network, database, repositories)
3. `:core:domain` — use cases, business logic
4. `:core:designsystem` — theme, common UI components (when ready for UI migration)
5. Feature UI modules — screen by screen

## Phase 1: Prepare the Codebase

These changes happen **before** any KMP plugin configuration. The Android app should keep
building and working throughout.

### 1.1 Replace Java-Only APIs

### 1.2 Ensure kotlin-test for Shared Modules

Modules that will become multiplatform need `kotlin-test` instead of JUnit. The migration
is usually straightforward — `kotlin-test` provides compatible annotations (`@Test`,
`assertEquals`, etc.). See the [kotlin-test documentation](https://kotlinlang.org/api/core/kotlin-test/).

### 1.3 Verify Compose Readiness (for UI Migration)

If you plan to share UI code with Compose Multiplatform:
- Confirm the project uses Jetpack Compose (not Android Views)
- Check that Compose dependencies are at versions compatible with Compose Multiplatform
- Identify any Android-specific Compose APIs used (e.g., `AnnotatedString.fromHtml()`)

## Phase 2: Migrate Business Logic Modules to KMP

Work through modules one at a time, following the dependency order from Step 0.

See [references/MODULE-MIGRATION.md](references/MODULE-MIGRATION.md) for detailed before/after build script examples and source set layout.

### For Each Module

#### 2.1 Update the Build Script

Replace the Android library plugin with the KMP configuration:

```kotlin
// Before                                    // After
plugins {                                    plugins {
    alias(libs.plugins.android.library)          alias(libs.plugins.android.multiplatform.library)
    alias(libs.plugins.kotlin.android)           // AGP 9: com.android.kotlin.multiplatform.library
}                                                // Older AGP: use kotlin.multiplatform + android.library
                                             }
```

Configure KMP targets:

```kotlin
kotlin {
    androidLibrary {
        // android target configuration
    }
    iosArm64()
    iosSimulatorArm64()

    // Optional: jvm() for Desktop, js()/wasmJs() for Web

    sourceSets {
        commonMain.dependencies {
            // Dependencies available on all platforms
        }
        androidMain.dependencies {
            // Android-specific dependencies
        }
        iosMain.dependencies {
            // iOS-specific dependencies
        }
    }
}
```

#### 2.2 Reorganize Source Sets

Move code from the Android layout to the KMP layout:

```
src/main/kotlin/ → src/commonMain/kotlin/    (shared code)
                 → src/androidMain/kotlin/   (Android-specific code)
src/test/kotlin/ → src/commonTest/kotlin/    (shared tests)
                 → src/androidUnitTest/kotlin/ (Android-specific tests)
```

Most code goes to `commonMain`. Code that uses Android APIs, Java APIs, or Android-only libraries stays in `androidMain`.

#### 2.3 Handle Platform-Specific Code with expect/actual

When shared code needs platform-specific behavior, use `expect`/`actual` declarations, for example:

```kotlin
// commonMain
expect fun createPlatformLogger(): Logger

// androidMain
actual fun createPlatformLogger(): Logger = AndroidLogger()

// iosMain
actual fun createPlatformLogger(): Logger = NSLogLogger()
```

**Prefer interfaces + DI over expect/actual** when:
- The abstraction is simple (just hiding an implementation behind an interface)
- You want testability (interfaces are easier to mock)
- Multiple implementations per platform might be needed

**Use expect/actual when:**
- You need compile-time enforcement that every platform provides an implementation
- The platform API surface is complex or deeply integrated
- You're wrapping platform types (like database builders, connectivity checkers)

See the official [expect/actual documentation](https://kotlinlang.org/docs/multiplatform/multiplatform-expect-actual.html) for the full set of rules and supported constructs.

#### 2.4 Verify the Module

After each module migration:
1. `./gradlew :<module>:build` should succeed
2. `./gradlew :<module>:allTests` should pass
3. The Android app should still build and run: `./gradlew :app:assembleDebug`

**If something breaks**, don't push forward. Diagnose the issue, and if it's not straightforward to fix, revert and report the problem to the user.

### Database Modules (Room)

Room has been multiplatform since version 2.7.0. Follow the [official Room KMP setup guide](https://developer.android.com/kotlin/multiplatform/room).
Key changes:
- Database builder becomes an `expect`/`actual` declaration
- Schema definition stays in `commonMain`
- Platform-specific database instantiation goes in `androidMain`/`iosMain`

### DI Modules

If the project uses Koin (already multiplatform), the DI layer typically migrates
smoothly — just move module definitions to `commonMain` and platform-specific bindings
to the respective source sets.

If the project uses Hilt/Dagger, this is a **prerequisite migration** to either Koin or Metro, that should happen separately before KMP migration. Flag it to the user.

## Phase 3: Migrate UI to Compose Multiplatform

Only proceed here after business logic modules are multiplatform.
See [references/UI-MIGRATION.md](references/UI-MIGRATION.md) for detailed guidance on resource migration, theme adaptation, and navigation patterns.

### 3.1 Create a Shared UI Module

Create a new module (or convert an existing one) for shared Compose Multiplatform code:

```kotlin
plugins {
    alias(libs.plugins.android.multiplatform.library) // AGP 9; older AGP: kotlin.multiplatform + android.library
    alias(libs.plugins.compose.multiplatform)
    alias(libs.plugins.compose.compiler)
}

kotlin {
    androidLibrary {
        // android target configuration
    }
    iosArm64()
    iosSimulatorArm64()

    // Optional: jvm() for Desktop, js()/wasmJs() for Web

    sourceSets {
        commonMain.dependencies {
            implementation(compose.runtime)
            implementation(compose.foundation)
            implementation(compose.material3)
            implementation(compose.ui)
            implementation(compose.components.resources)
        }
    }
}
```

### 3.2 Migrate Design System and Screens

Start with the design system (theme, typography, colors, shapes), then migrate screens one at a time. For each:

1. Move composables and ViewModels to `commonMain` (ViewModels only if they use shared dependencies)
2. Move resources from `res/` to `composeResources/` and replace `R.*` references with `Res.*`
3. Provide platform `expect`/`actual` where needed (e.g., dynamic colors on Android)
4. Update the navigation graph — migrated screens come from shared code, non-migrated screens stay in the Android module

### 3.3 Migrate Navigation

Navigation can migrate incrementally — inject platform-specific screens into the shared
navigation graph so migrated and non-migrated screens coexist. Once all screens are
migrated, the full navigation graph can live in shared code.
See [references/UI-MIGRATION.md](references/UI-MIGRATION.md) for code examples of mixed navigation graphs and platform screen injection

## Phase 4: Create Platform Entry Points and Wire Up Shared UI

Phases 1–3 extracted shared logic and UI from the Android app into multiplatform modules. Phase 4 creates the actual applications for other platforms that **use** that shared UI. The Android app already works — it was the starting point. Now build entry points for iOS (required), and optionally Desktop and Web.

### 4.1 Configure Framework Export in the Shared Module

Before creating platform apps, ensure the shared UI module exports a framework iOS can consume:

```kotlin
kotlin {
    listOf(iosArm64(), iosSimulatorArm64()).forEach {
        it.binaries.framework {
            baseName = "Shared"
            isStatic = true
        }
    }
}
```

If the project has multiple shared modules, create an **umbrella module** that depends on all of them and re-exports a single framework — iOS apps can only link against one KMP framework.

### 4.2 Create the Kotlin iOS Entry Point

Create a `ComposeUIViewController` factory function in `iosMain` of the shared UI module. This is the bridge between Kotlin Compose UI and UIKit:

```kotlin
// shared-ui/src/iosMain/kotlin/MainViewController.kt
import androidx.compose.ui.window.ComposeUIViewController

fun MainViewController() = ComposeUIViewController { App() }
```

where `App()` is the top-level shared composable (the same one the Android app calls from its `MainActivity`).

### 4.3 Create the Xcode Project (iOS App)

1. Create the `iosApp/` directory at the project root
2. Create the Xcode project structure:
   ```
   iosApp/
   ├── iosApp.xcodeproj/
   │   └── project.pbxproj
   ├── iosApp/
   │   ├── Info.plist
   │   ├── iOSApp.swift          (app entry point)
   │   └── ContentView.swift     (hosts the ComposeUIViewController)
   └── iosApp.xcworkspace/       (if using CocoaPods or SPM workspace)
   ```
3. **`iOSApp.swift`** — the `@main` app struct:
   ```swift
   import SwiftUI

   @main
   struct iOSApp: App {
       var body: some Scene {
           WindowGroup {
               ContentView()
           }
       }
   }
   ```
4. **`ContentView.swift`** — wraps the Compose UI in a SwiftUI view:
   ```swift
   import UIKit
   import SwiftUI
   import Shared

   struct ComposeView: UIViewControllerRepresentable {
       func makeUIViewController(context: Context) -> UIViewController {
           MainViewControllerKt.MainViewController()
       }
       func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
   }

   struct ContentView: View {
       var body: some View {
           ComposeView().ignoresSafeArea(.keyboard)
       }
   }
   ```
5. **Link the KMP framework** — configure the Xcode project to find the Shared framework. Manually add a Run Script build phase that invokes the `embedAndSignAppleFrameworkForXcode` Gradle task.

See the [official tutorial on integrating KMP into existing apps](https://kotlinlang.org/docs/multiplatform/multiplatform-integrate-in-existing-app.html) and the [iOS integration methods overview](https://kotlinlang.org/docs/multiplatform/multiplatform-ios-integration-overview.html).

**Swift interop notes:**
- Kotlin compiles to Objective-C, not Swift — use KMP-NativeCoroutines or SKIE to bridge `suspend` functions, `Flow`, and sealed classes to Swift-friendly APIs
- Kotlin generics are partially lost in Objective-C interop; expose concrete types to Swift where possible

### 4.4 Desktop (JVM) Entry Point (Optional)

Create a `desktopApp/` module with the `kotlin.jvm`, `compose.multiplatform`, and `compose.compiler` plugins. Wire it to the shared UI:

```kotlin
// desktopApp/src/main/kotlin/Main.kt
import androidx.compose.ui.window.Window
import androidx.compose.ui.window.application

fun main() = application {
   Window(
      onCloseRequest = ::exitApplication,
      title = "MyApplication",
   ) {
      App()
   }
}
```

Add `compose.desktop.currentOs` as a dependency and register a `compose.desktop.application` block with a `mainClass`.

### 4.5 Web Entry Point (Optional)

Create a `webApp/` module with `wasmJs` (or `js`) target. Wire it to the shared UI:

```kotlin
// webApp/src/wasmJsMain/kotlin/Main.kt
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.window.ComposeViewport

@OptIn(ExperimentalComposeUiApi::class)
fun main() {
   ComposeViewport {
      App()
   }
}
```

Add a minimal `index.html` in `src/webMain/resources/`.

### 4.6 Verify All Platforms Build

After creating entry points, build each platform app to verify the wiring is correct. Run these commands and confirm they succeed before considering Phase 4 complete.

> **Note:** The examples below use `:shared`, `:app`, `:desktopApp`, and `:webApp` as module names. Substitute the actual module names from the project (e.g., `:shared-ui`, `:core:shared`, `:androidApp`).

**Shared module (all targets):**
```bash
./gradlew :<shared-module>:build
```

**Android app:**
```bash
./gradlew :<android-app-module>:assembleDebug
```

**iOS app:**
```bash
xcodebuild \
  -project iosApp/iosApp.xcodeproj \
  -scheme iosApp \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -allowProvisioningUpdates \
  build
```
The `embedAndSignAppleFrameworkForXcode` Gradle task is invoked automatically by the Run Script build phase in the Xcode project — no need to build the framework separately. If the project uses a workspace (`.xcworkspace`), replace `-project` with `-workspace`. Adjust the scheme and project path to match the Xcode project.

**Desktop app (if added):**
```bash
./gradlew :<desktop-app-module>:build
```

**Web app (if added):**
```bash
./gradlew :<web-app-module>:wasmJsBrowserDistribution
```

**Shared module tests (all platforms):**
```bash
./gradlew :<shared-module>:allTests
```

## Verification

After the full migration (all phases), verify with the [checklist](assets/checklist.md). Key checks:

1. All platform build commands above succeed
2. Shared module tests pass
3. Android app runs correctly with no regressions
4. Source sets are correctly organized (`commonMain`, `androidMain`, `iosMain`)
5. No Android-only APIs in `commonMain` source sets
6. iOS app launches in the simulator and renders the shared Compose UI

## Common Issues

- **Missing stdlib APIs in common code** — `Dispatchers.IO`, `System.currentTimeMillis()`, `java.util.UUID` all need KMP replacements (see [DEPENDENCY-MAPPING.md](references/DEPENDENCY-MAPPING.md))
- **Compose resource naming** — directory must be `composeResources`, not `res`
- **Gradle memory** — KMP builds may need more memory; set `org.gradle.jvmargs=-Xmx4g` in `gradle.properties`

## Reference Files

- [Dependency Mapping](references/DEPENDENCY-MAPPING.md) — Android libraries and KMP alternatives
- [Module Migration](references/MODULE-MIGRATION.md) — detailed build script and source set conversion
- [UI Migration](references/UI-MIGRATION.md) — Compose to Compose Multiplatform migration
