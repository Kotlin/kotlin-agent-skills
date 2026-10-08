# CocoaPods Pod → SwiftPM Mapping (Migration)

Migration-specific guidance for replacing CocoaPods pods with SwiftPM packages: the pod→product name
correspondence, version-preservation rules, and the two classes of KMP wrapper libraries that need
special handling (bundled cinterop klibs, and CocoaPods-era linker metadata).

> **For the full per-library SPM configuration** — package URLs, `products`, `importedClangModules`,
> platform quirks, the combined Firebase example, the Crashlytics dSYM script, and Firebase's
> static-framework requirement — see the **`kotlin-tooling-spm-dependencies`** skill's
> `references/common-packages.md`. This file only adds the migration concerns on top of it.

## Pod → SPM Name Mapping

For most popular libraries the SPM product name equals the CocoaPods pod name. The notable
exceptions and the repositories to use:

| Pod Name | SPM Product | SPM Repository | Notes |
|----------|-------------|----------------|-------|
| FirebaseAnalytics / FirebaseAuth / FirebaseCore / FirebaseCrashlytics / FirebaseMessaging / FirebaseStorage / FirebaseInstallations / FirebaseAppCheck / FirebasePerformance | *(same name)* | firebase/firebase-ios-sdk.git | |
| FirebaseDatabase | FirebaseDatabase | firebase/firebase-ios-sdk.git | importedClangModules: `FirebaseDatabaseInternal` |
| FirebaseFirestore | FirebaseFirestore | firebase/firebase-ios-sdk.git | importedClangModules: `FirebaseFirestoreInternal` |
| FirebaseRemoteConfig | FirebaseRemoteConfig | firebase/firebase-ios-sdk.git | importedClangModules: `FirebaseRemoteConfigInternal` |
| FirebaseInAppMessaging | **FirebaseInAppMessaging-Beta** | firebase/firebase-ios-sdk.git | `-Beta` suffix; importedClangModules: `FirebaseInAppMessagingInternal` |
| FirebaseAppDistribution | **FirebaseAppDistribution-Beta** | firebase/firebase-ios-sdk.git | `-Beta` suffix |
| FirebaseABTesting | *(no product)* | firebase/firebase-ios-sdk.git | Module-only — `importedClangModules` only |
| FirebaseAILogic | **FirebaseAI** | firebase/firebase-ios-sdk.git | Renamed in SPM, Swift-only |
| GoogleMaps | GoogleMaps | googlemaps/ios-maps-sdk.git | iOS 16+ only; must use `exact()` |
| GoogleSignIn | GoogleSignIn | google/GoogleSignIn-iOS.git | |
| GoogleSignInSwiftSupport | **GoogleSignInSwift** | google/GoogleSignIn-iOS.git | SwiftUI support |
| LoremIpsum | LoremIpsum | lukaskubanek/LoremIpsum.git | |

See `kotlin-tooling-spm-dependencies`'s common-packages reference for the ready-made
`swiftPackage()` declarations and Clang-module details for each.

> **WARNING: Do not mix a library suite across CocoaPods and SPM during migration.** Suites that
> share a repository and transitive dependencies (e.g., all Firebase products) must move to SPM
> **together**. If some Firebase pods stay in CocoaPods while others are added via SPM, the shared
> transitive dependencies (gRPC, abseil, leveldb, BoringSSL, nanopb) get linked twice with
> conflicting symbols, causing **dyld crashes at runtime** (e.g.,
> `Symbol not found: _OBJC_CLASS_$_FIRFirestore`). Move all products of the suite at once —
> including Swift-only products (FirebaseAI, FirebaseFunctions, FirebaseMLModelDownloader) that
> Kotlin can't use directly; add those as `products` entries without `importedClangModules`. After
> adding products, re-run `integrateLinkagePackage`.

## Version Preservation (Migration Rule)

Do NOT bump dependency versions during migration — use the exact same version that was in the
`cocoapods {}` block. Bumping versions can resolve to a different library build that breaks cinterop
APIs (removed symbols, changed signatures) and introduces issues unrelated to the migration.

| CocoaPods version spec | SPM equivalent |
|------------------------|----------------|
| `version = "1.2.3"` (exact pin) | `exact("1.2.3")` (typed API) — CocoaPods `"X.Y.Z"` without `~>` is an exact pin |
| `version = "~> 1.2"` (optimistic) | `version = "1.2.0"` (simple) or `from("1.2.0")` (typed) |
| No version specified | Ask the user which version to pin |

Always check the library's GitHub releases page to confirm the exact version is available as an SPM
release.

---

## KMP Wrapper Libraries with Bundled Cinterop Klibs

Some KMP libraries that wrap iOS SDKs ship pre-built cinterop klibs using the `cocoapods.*` package
namespace. After migrating to SwiftPM, these `cocoapods.*` imports **must be preserved** — they
resolve to the library's bundled klib, not to actual CocoaPods infrastructure. The
`swiftPMDependencies` cinterop generator detects the existing bindings and **skips** generating new
ones for that Clang module, so `swiftPMImport.*` for those classes will fail with "Unresolved
reference".

### KMPNotifier

Repository: [https://github.com/mirzemehdi/KMPNotifier](https://github.com/mirzemehdi/KMPNotifier)
Maven: `io.github.mirzemehdi:kmpnotifier`

**What it provides:** A KMP push notification library that wraps Firebase Cloud Messaging on iOS. The library bundles its own cinterop klib with namespace `cocoapods.FirebaseMessaging`, providing Kotlin bindings for `FIRMessaging`, `FIRMessagingAPNSTokenType`, and related classes.

**Impact on migration:**
- When `swiftPMDependencies` generates cinterop bindings, it detects that `FirebaseMessaging` bindings already exist in KMPNotifier's klib and **skips generating new bindings** for that Clang module
- `import cocoapods.FirebaseMessaging.FIRMessaging` must remain unchanged — do NOT replace with `swiftPMImport.*`
- `FirebaseMessaging` should still be listed in `products` and `importedClangModules` for SPM linking, even though cinterop bindings won't be generated for it

**Verifying bundled klib contents:** Use `klib dump-metadata-signatures` to inspect what a library's klib provides ([docs](https://kotlinlang.org/docs/native-libraries.html#using-kotlin-native-compiler)):

```bash
find ~/.gradle/caches -name "*.klib" -path "*kmpnotifier*" | head -1
klib dump-metadata-signatures /path/to/cinterop.klib | grep "FIRMessaging"
# Shows: cocoapods.FirebaseMessaging/FIRMessaging → confirms bundled klib
```

**Example — project using both KMPNotifier and GoogleSignIn:**
```kotlin
// IOSDelegate.kt — after migration
import cocoapods.FirebaseMessaging.FIRMessaging           // KEEP — from kmpnotifier klib
import cocoapods.FirebaseMessaging.FIRMessagingAPNSTokenType  // KEEP — from kmpnotifier klib
import swiftPMImport.com.example.app.GIDSignIn            // REPLACE — direct cinterop
```

### dev.gitlive/firebase-kotlin-sdk

Repository: [https://github.com/GitLiveApp/firebase-kotlin-sdk](https://github.com/GitLiveApp/firebase-kotlin-sdk)
Maven: `dev.gitlive:firebase-auth`, `dev.gitlive:firebase-firestore`, `dev.gitlive:firebase-storage`, etc.

**What it provides:** Kotlin-first Firebase APIs for KMP. Unlike KMPNotifier, dev.gitlive libraries provide **high-level Kotlin APIs** — you typically don't use `cocoapods.*` imports directly. Instead, the Firebase pods were declared with `linkOnly = true` in CocoaPods to provide native linking only.

**Impact on migration:**

1. **Linker flags baked into published klibs.** The dev.gitlive klibs contain `-framework FirebaseCore`, `-framework FirebaseAuth`, etc. from the CocoaPods era. These persist when the consuming project switches to SPM. With SPM, Firebase frameworks land in per-product subdirectories (`$BUILT_PRODUCTS_DIR/FirebaseCore/FirebaseCore.framework`) that the K/N linker doesn't search automatically.

   **Fix:** Add per-product `-F` linkerOpts to `build.gradle.kts`:
   ```kotlin
   val builtProductsDir = System.getenv("BUILT_PRODUCTS_DIR")
   if (builtProductsDir != null) {
       listOf("FirebaseCore", "FirebaseAuth", "FirebaseCoreExtension",
              "FirebaseCoreInternal", "FirebaseCrashlytics", "FirebaseFirestore",
              "FirebaseFirestoreInternal", "FirebaseInstallations", "FirebaseMessaging",
              "FirebaseStorage", "GoogleDataTransport", "GoogleUtilities",
              "GTMSessionFetcher", "AppCheckCore", /* ... */).forEach { product ->
           linkerOpts("-F", "$builtProductsDir/$product")
       }
   }
   ```
   The `if (builtProductsDir != null)` guard ensures `./gradlew :moduleName:compileKotlinIosSimulatorArm64` works without Xcode (compilation doesn't link). Also add matching `FRAMEWORK_SEARCH_PATHS` in the Xcode project for both Debug and Release.

2. **Must use `isStatic = true`.** With a dynamic framework, the K/N linker creates `@rpath/FirebaseCore.framework/FirebaseCore` load instructions. Firebase SPM products are static libraries — their `.framework` bundles are not embedded in the app bundle. At runtime, `dyld` crashes with `Library not loaded`. Switching to `isStatic = true` embeds all symbols and defers unresolved framework flags to the final Xcode link.

3. **iOS test tasks may fail.** The K/N test runner cannot find Firebase frameworks outside of Xcode context. You may need to disable iOS test tasks:
   ```kotlin
   tasks.matching {
       (it.name.contains("Ios") || it.name.contains("ios")) &&
           (it.name.contains("Test") || it.name.contains("test"))
   }.configureEach { enabled = false }
   ```

### Identifying Bundled Cinterop Klibs in Unknown Libraries

If you suspect a KMP library bundles its own cinterop klibs (common for libraries wrapping iOS SDKs), use the `klib` tool to inspect them ([docs](https://kotlinlang.org/docs/native-libraries.html#using-kotlin-native-compiler)):

```bash
# Find klibs from a specific library in Gradle caches
find ~/.gradle/caches -name "*.klib" -path "*libraryName*"

# Dump API signatures to see what namespaces and classes are provided
klib dump-metadata-signatures /path/to/library.klib | grep "cocoapods\."

# If output shows cocoapods.* entries, the library bundles cinterop klibs.
# Those cocoapods.* imports must be preserved after migration.
```

Indicators that a library may bundle cinterop klibs:
- The project has `linkOnly = true` pod declarations for the same native SDK
- The library's documentation mentions CocoaPods integration or cinterop
- The library provides Kotlin APIs for an iOS SDK (Firebase, Maps, etc.)
