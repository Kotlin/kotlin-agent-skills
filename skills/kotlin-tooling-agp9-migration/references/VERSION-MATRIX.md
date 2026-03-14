# Version Compatibility Matrix for KMP AGP 9.0 Migration

---

## Core Compatibility Table

| Component | Minimum | Recommended | Notes |
|---|---|---|---|
| AGP | 9.0.0 | 9.0.1+ | 9.0.0 is initial release; 9.0.1+ includes early bug fixes |
| Gradle | 9.1.0 | 9.1.0+ | AGP 9.0 requires Gradle 9.1+; earlier Gradle versions will not work |
| JDK | 17 | 17+ | AGP 9.0 requires JDK 17 minimum |
| SDK Build Tools | 36.0.0 | 36.0.0 | Required by AGP 9.0 |
| KGP (Kotlin Gradle Plugin) | 2.0.0 | 2.3.0+ | 2.0.0 is minimum for KMP library plugin; 2.3.0+ has best compatibility |
| KGP (built-in Kotlin runtime) | 2.2.10 | 2.3.0+ | AGP 9.0 has runtime dependency on KGP 2.2.10; auto-upgrades if lower |
| KSP (with built-in Kotlin) | 2.2.10-2.0.2 | Matches KGP | Auto-upgraded to match KGP when using built-in Kotlin |
| NDK | — | r28c (28.2.13676358) | Default changed to r28c; specify explicitly if needed |
| Android Studio | Otter 3 FD (2025.2.3) | Latest stable | First version with full AGP 9.0 + KMP library plugin IDE support |
| IntelliJ IDEA | Not supported | — | Does not support AGP 9.0; use Android Studio instead |
| Max API Level | — | 36.1 | Highest supported API level in AGP 9.0 |

---

## Extended Compatibility

| Component | Minimum | Recommended | Notes |
|---|---|---|---|
| Compose Multiplatform | 1.7.0 | 1.8.0+ | 1.7.0 works but 1.8.0+ has improved AGP 9.0 integration |
| Compose Compiler Plugin | 2.0.0 | Matches KGP version | Since KGP 2.0, use `org.jetbrains.kotlin.plugin.compose` — version is tied to KGP automatically |
| KSP | 2.0.0-1.0.21 | Matches KGP version | Version format: {KGP version}-{KSP version} |
| Kotlin Coroutines | 1.8.0 | 1.10.0+ | 1.8.0+ for full K2 support |
| Ktor | 2.3.0 | 3.0.0+ | 3.0.0 for best KMP library plugin compatibility |
| Room (KMP) | 2.7.0-alpha01 | 2.7.0+ | KMP Room requires KSP; verify KSP compatibility |
| kotlinx.serialization | 1.6.0 | 1.8.0+ | 1.8.0+ for K2 compiler plugin support |

---

## Version Notes

### AGP 9.0.0

- First release supporting `com.android.kotlin.multiplatform.library`.
- Built-in Kotlin compilation for `com.android.application` and `com.android.library` (no separate `kotlin-android` plugin needed).
- Removes support for `com.android.application` + `org.jetbrains.kotlin.multiplatform` in the same module.
- Single-variant model for KMP libraries (no build types/flavors).
- Runtime dependency on KGP 2.2.10 — projects using lower KGP versions are auto-upgraded.
- KSP auto-upgraded to 2.2.10-2.0.2 to match the built-in KGP version.
- New DSL interfaces only — `BaseExtension` and legacy types removed.
- `org.jetbrains.kotlin.kapt` incompatible — use KSP or `com.android.legacy-kapt`.
- Java source/target default changed from Java 8 to Java 11.
- R class is compile-time non-final in application modules by default.
- `targetSdk` defaults to `compileSdk` when not set (was `minSdk`).
- NDK default changed to r28c.
- Requires JDK 17+, Gradle 9.1.0+, SDK Build Tools 36.0.0.
- Many Gradle properties defaults changed — see SKILL.md "Gradle Properties Default Changes".
- Removed: embedded Wear OS app support, density split APKs, legacy variant APIs.
- New: IDE support for test fixtures, fused library plugin (preview).

### AGP 9.0.1+

- Bug fixes for KMP library plugin edge cases.
- Improved error messages for common migration mistakes.
- Better IDE sync performance.

### Gradle 9.1.0

- Required minimum for AGP 9.
- Configuration cache fully stable.
- Improved Kotlin DSL performance.
- New dependency resolution APIs used by AGP 9.

### KGP 2.2.10

- Runtime dependency version for AGP 9.0's built-in Kotlin.
- Projects on lower KGP are auto-upgraded to this version at build time.
- KSP is correspondingly upgraded to 2.2.10-2.0.2.
- To use a higher KGP version, add it explicitly to `buildscript.dependencies`.

### KGP 2.0.0

- Minimum for the KMP library plugin to function.
- K2 compiler is the default.
- New `compilerOptions` DSL (replaces `kotlinOptions`).

### KGP 2.3.0+

- Best compatibility with KMP AGP 9.0 library plugin.
- Improved multiplatform source set inference.
- Better error diagnostics for KMP configuration issues.
- Stable Compose compiler plugin integration.

### Android Studio Otter 3 FD (2025.2.3)

- First version with full AGP 9.0 support.
- KMP library plugin DSL code completion and navigation.
- Correct source set detection for `androidHostTest` / `androidDeviceTest`.
- Run configuration support for KMP library module tests.

### IntelliJ IDEA

- Does **not** support AGP 9.0 as of 2025.3.
- Android/KMP projects targeting AGP 9.0 should use Android Studio instead.
- IntelliJ IDEA can still be used for non-Android KMP targets (JVM, iOS, JS/Wasm).

---

## Upgrade Path

### From AGP 8.x + KGP 1.9.x

1. Upgrade KGP to 2.0.0+ first (can be done on AGP 8.x).
2. Migrate `kotlinOptions` to `compilerOptions`.
3. Upgrade Gradle to 9.1.0.
4. Upgrade AGP to 9.0.1+.
5. Migrate library plugins to `com.android.kotlin.multiplatform.library`.
6. Upgrade KGP to 2.3.0+ for best experience.

### From AGP 8.x + KGP 2.0.x

1. Upgrade Gradle to 9.1.0.
2. Upgrade AGP to 9.0.1+.
3. Migrate library plugins to `com.android.kotlin.multiplatform.library`.
4. Upgrade KGP to 2.3.0+ for best experience.

---

## gradle/wrapper/gradle-wrapper.properties

```properties
distributionUrl=https\://services.gradle.org/distributions/gradle-9.1-bin.zip
```

---

## libs.versions.toml Template

```toml
[versions]
agp = "9.0.1"
kotlin = "2.3.0"
ksp = "2.3.0-1.0.30"
compose-multiplatform = "1.8.0"
coroutines = "1.10.1"
ktor = "3.0.3"
serialization = "1.8.0"

[plugins]
androidApplication = { id = "com.android.application", version.ref = "agp" }
androidKmpLibrary = { id = "com.android.kotlin.multiplatform.library", version.ref = "agp" }
kotlinMultiplatform = { id = "org.jetbrains.kotlin.multiplatform", version.ref = "kotlin" }
kotlinJvm = { id = "org.jetbrains.kotlin.jvm", version.ref = "kotlin" }
composeMultiplatform = { id = "org.jetbrains.compose", version.ref = "compose-multiplatform" }
composeCompiler = { id = "org.jetbrains.kotlin.plugin.compose", version.ref = "kotlin" }
kotlinxSerialization = { id = "org.jetbrains.kotlin.plugin.serialization", version.ref = "kotlin" }
ksp = { id = "com.google.devtools.ksp", version.ref = "ksp" }
```

---

## Compatibility Validation Commands

Run these to verify your setup is compatible:

```bash
# Check Gradle version
./gradlew --version

# Check AGP version applied
./gradlew buildEnvironment | grep "com.android"

# Check KGP version
./gradlew buildEnvironment | grep "org.jetbrains.kotlin"

# Verify the KMP library plugin is recognized
./gradlew :shared:tasks --group=build

# Full validation build
./gradlew :shared:assemble :androidApp:assembleDebug
```
