# KMP AGP 9.0 Migration Verification Checklist

Use this checklist after migration to verify everything is configured correctly.

## Build Verification
- [ ] `./gradlew build` succeeds
- [ ] `./gradlew :androidApp:assembleDebug` succeeds (if app module)
- [ ] No deprecation warnings about variant API or DSL

## Plugin Configuration
- [ ] No `com.android.library` or `com.android.application` in KMP modules' build.gradle.kts
- [ ] No `org.jetbrains.kotlin.android` plugin in any AGP 9.0 module (built-in Kotlin replaces it)
- [ ] No `org.jetbrains.kotlin.kapt` plugin — migrated to KSP or `com.android.legacy-kapt`
- [ ] `com.android.kotlin.multiplatform.library` plugin declared (in version catalog or build files directly)
- [ ] Third-party plugins verified compatible 

## Built-in Kotlin
- [ ] `org.jetbrains.kotlin.android` removed from all build files and version catalog
- [ ] `android.kotlinOptions {}` migrated to `kotlin { compilerOptions {} }`
- [ ] `kotlin.sourceSets` migrated to `android.sourceSets` with `.kotlin` accessor (non-KMP modules)
- [ ] No `android.builtInKotlin=false` unless required by incompatible plugin (documented as temporary)

## Source Sets
- [ ] Source sets renamed: androidMain, androidHostTest, androidDeviceTest
- [ ] No `android {}` top-level block in KMP library modules

## Android-Specific Features
- [ ] `androidResources { enable = true }` present if module uses Android resources
- [ ] `withJava()` present if module has .java source files

## Testing
- [ ] Tests configured: `withHostTest {}`, `withDeviceTest {}`

## Dependencies (KMP Library Modules)
- [ ] No `debugImplementation` in KMP library modules — use `androidRuntimeClasspath` for tooling (app modules can still use `debugImplementation`)

## ProGuard / R8
- [ ] Consumer ProGuard rules migrated to `consumerProguardFiles.add(file(...))` in new DSL
- [ ] Using `proguard-android-optimize.txt` (not `proguard-android.txt`)
- [ ] No global options (`-dontobfuscate`, `-dontoptimize`) in library consumer rules
- [ ] Keep rules updated for R8 strict full mode (explicit default constructor rules if needed)
- [ ] No references to removed properties: `android.r8.integratedResourceShrinking`, `android.enableNewResourceShrinker.preciseShrinking`

## Gradle Properties
- [ ] No `android.enableLegacyVariantApi` in gradle.properties (removed in AGP 9.0, causes error)
- [ ] No `android.r8.integratedResourceShrinking` (causes error)
- [ ] No `android.enableNewResourceShrinker.preciseShrinking` (causes error)
- [ ] Any opt-out flags (`android.newDsl=false`, `android.builtInKotlin=false`) documented with reason
- [ ] `targetSdk` explicitly set in all app modules (defaults to compileSdk now)
- [ ] Unique `namespace` for each library module (`android.uniquePackageNames=true` is default)

## Module Structure
- [ ] Different namespaces for app module and library modules

## Version Requirements
- [ ] Gradle wrapper updated to 9.1.0+
- [ ] JDK 17+ in use
- [ ] SDK Build Tools 36.0.0 installed
- [ ] NDK version explicitly set if using native code (default changed to r28c)

## Build Logic / Convention Plugins
- [ ] No references to `BaseExtension`, `AppExtension`, `LibraryExtension` (removed)
- [ ] Using `CommonExtension` or specific new DSL types
- [ ] No use of removed APIs: `applicationVariants`, `libraryVariants`, `variantFilter`

## Runtime Verification
- [ ] Run configurations point to correct modules
- [ ] All platform entry points verified (Android, Desktop, Web, iOS)
- [ ] Release build tested (R8 rule changes may cause runtime issues)
- [ ] No `switch` statements on R class fields (non-final now in app modules)
