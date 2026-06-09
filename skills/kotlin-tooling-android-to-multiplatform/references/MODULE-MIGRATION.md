# Module Migration: Detailed Guide

Step-by-step instructions for converting an Android library module to a KMP module.

## Table of Contents

1. [Build Script Conversion](#build-script-conversion)
2. [Source Set Layout](#source-set-layout)
3. [Dependency Configuration](#dependency-configuration)
4. [Android-Specific Configuration](#android-specific-configuration)
5. [Test Configuration](#test-configuration)

---

## Build Script Conversion

### Before: Android Library Module

```kotlin
// module/build.gradle.kts
plugins {
    alias(libs.plugins.android.library)        // AGP 9 with built-in Kotlin; older AGP also has kotlin.android
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "com.example.core.data"
    compileSdk = 35

    defaultConfig {
        minSdk = 24
    }
}

dependencies {
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.ktor.client.okhttp)
    implementation(libs.room.runtime)
    ksp(libs.room.compiler)

    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
}
```

### After: KMP Module

```kotlin
// module/build.gradle.kts
plugins {
    alias(libs.plugins.android.multiplatform.library) // AGP 9: com.android.kotlin.multiplatform.library
    alias(libs.plugins.kotlin.serialization)          // Older AGP: use kotlin.multiplatform + android.library
}

kotlin {
    androidLibrary {
        namespace = "com.example.core.data"
        compileSdk = 35
        minSdk = 24
    }

    iosArm64()
    iosSimulatorArm64()

    // Optional: add jvm() for desktop, js()/wasmJs() for web

    sourceSets {
        commonMain.dependencies {
            implementation(libs.kotlinx.coroutines.core)
            implementation(libs.kotlinx.serialization.json)
        }

        androidMain.dependencies {
            implementation(libs.ktor.client.okhttp)
            implementation(libs.room.runtime)
        }

        iosMain.dependencies {
            implementation(libs.ktor.client.darwin)
        }

        commonTest.dependencies {
            implementation(libs.kotlin.test)
            implementation(libs.kotlinx.coroutines.test)
        }
    }
}
```

> **Older AGP (8.x):** Use `kotlin.multiplatform` + `android.library` plugins instead, with `androidTarget {}` and a separate `android {}` block for namespace/compileSdk. See the `kotlin-tooling-agp9-migration` skill for upgrading.

---

## Source Set Layout

### KMP Source Set Structure

```
module/
└── src/
    ├── commonMain/
    │   └── kotlin/
    │       └── com/example/core/data/
    │           ├── repository/
    │           │   └── PodcastRepository.kt     ← shared interface + implementation
    │           ├── model/
    │           │   └── Podcast.kt               ← shared data classes
    │           └── Platform.kt                  ← expect declarations
    ├── commonTest/
    │   └── kotlin/
    │       └── com/example/core/data/
    │           └── PodcastRepositoryTest.kt     ← shared tests
    ├── androidMain/
    │   └── kotlin/
    │       └── com/example/core/data/
    │           └── Platform.android.kt          ← actual declarations for Android
    ├── androidHostTest/                         ← AGP 9; older AGP: androidUnitTest
    │   └── kotlin/
    ├── iosMain/
    │   └── kotlin/
    │       └── com/example/core/data/
    │           └── Platform.ios.kt              ← actual declarations for iOS
    └── iosTest/
        └── kotlin/
```

### Moving Code

**Rule of thumb:** Move everything to `commonMain` first, then move things back to
platform source sets only when the compiler tells you something isn't available on all
platforms.

Common patterns that need to move to `androidMain`:
- Code using `android.*` packages (Context, SharedPreferences, etc.)
- Code using `java.*` packages that doesn't have KMP equivalents
- Android resource access (`R.string.*`, `R.drawable.*`)
- AndroidManifest-related code

**Preserve package names** when moving files. This minimizes import changes across
the rest of the codebase.

### Intermediate Source Sets

For iOS targets, KMP automatically creates a shared `iosMain` source set when you define
multiple iOS targets. Code in `iosMain` is shared across all iOS architectures:

```kotlin
kotlin {
    iosArm64()
    iosSimulatorArm64()
    // iosMain source set is automatically available
}
```

If targeting Desktop (`jvm`) or Web (`js`/`wasmJs`) in addition to Android and iOS, you can create intermediate source sets to share code between platform groups (e.g., a `jvmMain` for Android + Desktop). See the [hierarchical project structure docs](https://kotlinlang.org/docs/multiplatform/multiplatform-hierarchy.html).

---

## Dependency Configuration

### Dependency Scope Mapping

| Android scope                        | KMP equivalent                                                    |
|--------------------------------------|-------------------------------------------------------------------|
| `implementation(...)`                | `commonMain.dependencies { implementation(...) }` for shared deps |
| `implementation(...)` (Android-only) | `androidMain.dependencies { implementation(...) }`                |
| `testImplementation(...)`            | `commonTest.dependencies { implementation(...) }`                 |
| `androidTestImplementation(...)`     | Android device test dependencies                                  |
| `ksp(...)`                           | Configure per-target; see KSP section below                       |

### KSP in KMP

KSP configuration in KMP requires per-target setup:

```kotlin
dependencies {
    add("kspAndroid", libs.room.compiler)
    // For other targets:
    // add("kspIosX64", libs.some.processor)
    // add("kspIosArm64", libs.some.processor)
    // add("kspIosSimulatorArm64", libs.some.processor)
}
```

### Version Catalog Additions

Typical additions to `gradle/libs.versions.toml` for KMP:

```toml
[versions]
kotlin = "2.1.0"   # or latest
ktor = "3.1.0"
kotlinx-datetime = "0.6.2"
kotlinx-coroutines = "1.10.1"

[libraries]
kotlinx-coroutines-core = { module = "org.jetbrains.kotlinx:kotlinx-coroutines-core", version.ref = "kotlinx-coroutines" }
kotlinx-datetime = { module = "org.jetbrains.kotlinx:kotlinx-datetime", version.ref = "kotlinx-datetime" }
ktor-client-core = { module = "io.ktor:ktor-client-core", version.ref = "ktor" }
ktor-client-okhttp = { module = "io.ktor:ktor-client-okhttp", version.ref = "ktor" }
ktor-client-darwin = { module = "io.ktor:ktor-client-darwin", version.ref = "ktor" }

[plugins]
android-multiplatform-library = { id = "com.android.kotlin.multiplatform.library" } # AGP 9; older AGP: kotlin-multiplatform + android-library
```

---

## Android-Specific Configuration

### Resources

If the module uses Android resources, they remain in the `androidMain` source set:

```
module/src/androidMain/res/
    ├── values/
    │   └── strings.xml
    └── drawable/
        └── icon.xml
```

With AGP 9, Android resources need explicit enablement:

```kotlin
kotlin {
    androidLibrary {
        androidResources.enable = true
    }
}
```

### ProGuard Rules

Consumer ProGuard rules in KMP modules:

```kotlin
kotlin {
    androidLibrary {
        consumerProguardFiles.add(file("consumer-rules.pro"))
    }
}
// Older AGP: use android { defaultConfig { consumerProguardFiles("consumer-rules.pro") } }
```

---

## Test Configuration

### Shared Tests

Tests in `commonTest` run on all platforms:

```kotlin
// src/commonTest/kotlin/com/example/PodcastRepositoryTest.kt
import kotlin.test.Test
import kotlin.test.assertEquals

class PodcastRepositoryTest {
    @Test
    fun testGetPodcast() {
        // This test runs on Android, iOS, and JVM
        assertEquals("expected", "expected")
    }
}
```

### Platform-Specific Tests

Tests that need platform APIs go in platform test source sets:

- `androidHostTest/` — Android unit tests (run on JVM with Android stubs; older AGP: `androidUnitTest/`)
- `iosTest/` — iOS tests (run on iOS simulator)

### Running Tests

```bash
# All tests on all platforms
./gradlew :module:allTests

# Android unit tests only
./gradlew :module:testDebugUnitTest

# iOS tests (requires macOS)
./gradlew :module:iosSimulatorArm64Test
```

