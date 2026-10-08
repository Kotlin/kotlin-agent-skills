# Migration Troubleshooting Guide

CocoaPods-removal-specific issues. **For generic SPM problems** — import-not-found / namespace
mistakes, Gradle sync, missing-symbols/linker errors, "No such module", build-phase ordering, script
sandboxing, Firebase C++ cinterop failures, wrong Clang module names, Firebase Crashlytics dSYM,
Firebase beta product names, Google Maps version resolution, KSP, manual integration-command
discovery, and manual Xcode integration steps — see the **`kotlin-tooling-spm-dependencies`** skill's
`references/troubleshooting.md`. This file covers only what is specific to removing CocoaPods.

---

## Integration Task Issues

### `integrateEmbedAndSign` Skipped or Does Nothing

**Symptom:** Running `integrateEmbedAndSign` completes without errors but the Xcode project is not modified. The `embedAndSignAppleFrameworkForXcode` build phase is not added or remains commented out.

**Cause:** The project has code that disables `EmbedAndSign` tasks. Common patterns:

```kotlin
// In root or module build.gradle.kts
project.gradle.taskGraph.whenReady {
    allTasks.filter { it::class.simpleName?.contains("EmbedAndSign") == true }.forEach {
        it.enabled = false
    }
}
```

This was a CocoaPods-era workaround that inadvertently disables `integrateEmbedAndSign`.

**Solution:** Remove the disabler code from `build.gradle.kts`, then re-run the integration command.

---

### `embedAndSignAppleFrameworkForXcode` Commented Out in Build Phase

**Symptom:** Xcode build succeeds but produces no Kotlin framework. The app crashes at runtime with missing module errors.

**Cause:** The Gradle invocation in the Xcode build phase script was commented out (prefixed with `#`) — possibly a pre-existing state from before migration.

**Solution:** Open `project.pbxproj` and uncomment the Gradle invocation:

```diff
-#./gradlew :moduleName:embedAndSignAppleFrameworkForXcode
+./gradlew :moduleName:embedAndSignAppleFrameworkForXcode
```

---

## Third-Party KMP Libraries with Bundled Klibs

### `cocoapods.*` Class Not Found After Converting to `swiftPMImport.*`

**Symptom:** After replacing `import cocoapods.FirebaseMessaging.FIRMessaging` with `import swiftPMImport.<group>.<module>.FIRMessaging`, the build fails with `Unresolved reference 'FIRMessaging'`. Other swiftPMImport classes (e.g., `GIDSignIn`) resolve fine.

**Cause:** A third-party KMP library (e.g., [KMPNotifier](https://github.com/mirzemehdi/KMPNotifier) — `io.github.mirzemehdi:kmpnotifier`) bundles its own pre-built cinterop klib with the `cocoapods.FirebaseMessaging` namespace. The swiftPMDependencies cinterop generator detects these existing bindings and **deliberately skips** generating new bindings for that Clang module to avoid duplicate symbols. The `swiftPMImport.*` bindings for that module simply don't exist.

**Solution:** Revert the affected imports back to `cocoapods.*`:

```kotlin
// These resolve to the third-party library's bundled klib, NOT actual CocoaPods
import cocoapods.FirebaseMessaging.FIRMessaging
import cocoapods.FirebaseMessaging.FIRMessagingAPNSTokenType
```

The `cocoapods` prefix here is just a package namespace embedded in the library's published artifact — no CocoaPods infrastructure is needed at runtime.

**How to identify bundled klibs in advance:** Check if the project depends on KMP libraries that wrap iOS SDKs. Known libraries: [KMPNotifier](https://github.com/mirzemehdi/KMPNotifier) (bundles `cocoapods.FirebaseMessaging`). Also check for `linkOnly = true` pod declarations — this indicates the pod was only needed for linking while a KMP library provided the actual bindings. See [common-pods-mapping.md](common-pods-mapping.md) § "KMP Wrapper Libraries with Bundled Cinterop Klibs".

**Inspecting klib contents:** Use `klib dump-metadata-signatures` to verify which classes a klib provides ([docs](https://kotlinlang.org/docs/native-libraries.html#using-kotlin-native-compiler)):

```bash
# Find the klib
find ~/.gradle/caches -name "*.klib" -path "*kmpnotifier*" | head -1

# Dump and search for the class in question
klib dump-metadata-signatures /path/to/cinterop.klib | grep "FIRMessaging"
# Output shows: cocoapods.FirebaseMessaging.FIRMessaging → confirms bundled klib
```

You can also compare before/after migration by dumping the swiftPMImport klib:
```bash
# After build, find the swiftPMImport klib
find . -name "*.klib" -path "*swiftPMImport*" | head -1

# Verify which classes are available
klib dump-metadata-signatures /path/to/swiftPMImport.klib | grep "FIRMessaging"
# Empty output = class NOT in swiftPMImport (must use cocoapods.* import)
```

---

## dev.gitlive/firebase-kotlin-sdk Issues

These arise because dev.gitlive klibs were published with CocoaPods-era cinterop metadata. See also
[common-pods-mapping.md](common-pods-mapping.md) § dev.gitlive for the setup-time configuration.

### `framework 'FirebaseCore' not found` (K/N Linker)

**Symptom:** Kotlin/Native linker fails with:
```
ld: framework 'FirebaseCore' not found
```
or similar errors for `FirebaseAuth`, `FirebaseFirestore`, etc. The Gradle compilation succeeds but the link step fails.

**Cause:** [firebase-kotlin-sdk](https://github.com/GitLiveApp/firebase-kotlin-sdk) (`dev.gitlive:firebase-*`) was published with CocoaPods-era cinterop klibs. These klibs have `-framework FirebaseCore`, `-framework FirebaseAuth`, etc. baked into their linker metadata. With CocoaPods, those frameworks were in `Pods/` on the search path. With SPM, they land in per-product subdirectories (`$BUILT_PRODUCTS_DIR/FirebaseCore/FirebaseCore.framework`) that the K/N linker doesn't search.

**Solution (two-part):**

**Part A — Gradle linkerOpts:**
```kotlin
iosTarget.binaries.framework {
    val builtProductsDir = System.getenv("BUILT_PRODUCTS_DIR")
    if (builtProductsDir != null) {
        listOf(
            "FirebaseCore", "FirebaseAuth", "FirebaseCoreExtension",
            "FirebaseCoreInternal", "FirebaseCrashlytics", "FirebaseFirestore",
            "FirebaseFirestoreInternal", "FirebaseInstallations", "FirebaseMessaging",
            "FirebaseStorage", "GoogleDataTransport", "GoogleUtilities",
            "GTMSessionFetcher", "AppCheckCore", "AppAuth", "GTMAppAuth",
        ).forEach { product ->
            linkerOpts("-F", "$builtProductsDir/$product")
        }
    }
}
```

The `if (builtProductsDir != null)` guard ensures `./gradlew :moduleName:compileKotlinIosSimulatorArm64` works without Xcode (compilation doesn't link).

**Part B — Xcode FRAMEWORK_SEARCH_PATHS:**

Add matching entries in `project.pbxproj` for both Debug and Release `buildSettings`:
```
FRAMEWORK_SEARCH_PATHS = (
    "$(inherited)",
    "$(BUILT_PRODUCTS_DIR)/FirebaseCore",
    "$(BUILT_PRODUCTS_DIR)/FirebaseAuth",
    "$(BUILT_PRODUCTS_DIR)/FirebaseCoreExtension",
    // ... same list as Part A ...
);
```

---

### `dyld: Library not loaded: @rpath/FirebaseCore.framework/FirebaseCore` (Runtime Crash)

**Symptom:** The Gradle build and Xcode compilation both succeed, but the app crashes at launch with:
```
dyld: Library not loaded: @rpath/FirebaseCore.framework/FirebaseCore
  Referenced from: .../ComposeApp.framework/ComposeApp
```

**Cause:** The KMP framework is **dynamic** (`isStatic = false` or default). The K/N linker creates `LC_LOAD_DYLIB` entries (`@rpath/FirebaseCore.framework/FirebaseCore`). Firebase SPM products are **static** libraries — their `.framework` bundles exist in `$BUILT_PRODUCTS_DIR` during build but are NOT embedded in the app bundle. At runtime, `dyld` searches `@rpath` and finds nothing.

**Solution:** Switch to a static framework:

```kotlin
iosTarget.binaries.framework {
    baseName = "Shared"
    isStatic = true  // Required when using dev.gitlive:firebase-* with SPM
}
```

With a static framework, all symbols are embedded in the `.a` archive. No `LC_LOAD_DYLIB` entries are created. Unresolved `-framework` flags from dev.gitlive klibs are deferred to the final Xcode app link, where `KotlinMultiplatformLinkedPackage` provides them.

**After switching to static, also:**
1. Re-run `integrateLinkagePackage` — regenerates `Package.swift` with `type: .none` (static)
2. Remove any "Embed Frameworks" copy phase for the KMP framework — static frameworks must NOT be embedded
3. Add linker flags previously resolved by the K/N linker (e.g., `-framework Accelerate`, `-weak_framework CoreML`) to `OTHER_LDFLAGS` in the Xcode project

---

### dyld Crash When Mixing Firebase Across CocoaPods and SPM

**Symptom:** App crashes at launch with a dyld error like:
```
Symbol not found: _OBJC_CLASS_$_FIRFirestore
```
or similar `_OBJC_CLASS_$_FIR*` symbol-not-found errors. The Gradle build and Xcode compilation both succeed, but the app crashes at runtime.

**Cause:** Some Firebase pods were migrated to SPM while others remained in CocoaPods. All Firebase products share transitive dependencies (gRPC, abseil, leveldb, BoringSSL, nanopb). Having both package managers link these transitive dependencies causes duplicate/conflicting symbols that the dynamic linker cannot resolve.

**Solution:** Migrate **all** Firebase pods to SPM at once. This includes Swift-only pods (FirebaseAI, FirebaseFunctions, FirebaseMLModelDownloader) that Kotlin cannot use directly — add them as `products` entries without `importedClangModules`:

```kotlin
products = listOf(
    // ObjC pods used by Kotlin:
    product("FirebaseAnalytics"),
    product("FirebaseAuth"),
    // ...
    // Swift-only pods (no importedClangModules needed):
    product("FirebaseAI"),
    product("FirebaseFunctions"),
),
```

After adding new products, re-run `integrateLinkagePackage` to regenerate the linkage Swift package.

---

## Manual CocoaPods Deintegration from pbxproj

If `pod deintegrate` is not available, manually remove these CocoaPods references from `project.pbxproj`:

- `Pods_<target>.framework` build file and file reference
- `Pods-<target>.debug.xcconfig` / `Pods-<target>.release.xcconfig` file references
- `Pods` group and `Frameworks` group (if it only contained the Pods framework)
- `[CP] Check Pods Manifest.lock` shell script build phase
- `[CP] Embed Pods Frameworks` shell script build phase
- `baseConfigurationReference` lines pointing to Pods xcconfig files

Also remove `Pods/` from `.gitignore` and delete the `.xcworkspace` directory.

---

## When Build Fails After Migration

**Do NOT revert the migration as a first response.** Instead:

1. **Read the full error log** — identify the actual failure type (Gradle resolution, import not found, linker error, Xcode build phase).
2. **Re-check each migration phase** — walk through Phases 2-6 and verify each step was applied. Common migration-specific mistakes:
   - Wrong `group` or module name in import namespace (dashes not converted to dots)
   - `cocoapods {}` block or plugin not fully removed (Phase 6)
   - Wrong Xcode project file opened (`.xcodeproj` when non-KMP CocoaPods remain and `.xcworkspace` is needed, or vice versa)
   - `isStatic = true` missing from framework config (required with dev.gitlive or similar CocoaPods-era wrapper klibs)
   - `integrateLinkagePackage` not run
   - EmbedAndSign disabler code not removed (prevents `integrateEmbedAndSign`)
   - `embedAndSignAppleFrameworkForXcode` commented out in Xcode build phase
   - `cocoapods.*` imports replaced that should have been preserved (bundled klib from third-party library)
3. **Consult the sections above** (migration-specific) and the `kotlin-tooling-spm-dependencies` skill's troubleshooting (generic SPM errors).
4. **If unsure, present options to the user** — describe what the logs show, list possible causes, and let the user decide.

---

## Rollback Instructions (Last Resort)

Only revert if the analysis above does not resolve the issue:

### Step 1: Restore Git Files

```bash
# Restore CocoaPods files (adjust path if iOS project is not in iosApp/)
git checkout -- "**/Podfile" "**/Podfile.lock"
git checkout -- *.podspec
git checkout -- **/build.gradle.kts
git checkout -- **/src/**/*.kt
```

### Step 2: Restore CocoaPods in build.gradle.kts

```kotlin
plugins {
    kotlin("native.cocoapods")  // Re-add
}

kotlin {
    cocoapods {
        // Restore original configuration
    }
    // Remove swiftPMDependencies block
}
```

### Step 3: Restore Kotlin Imports

Change all imports back:
```kotlin
// FROM:
import swiftPMImport.group.module.ClassName

// TO:
import cocoapods.PodName.ClassName
```

### Step 4: Reinstall CocoaPods

```bash
# Navigate to directory containing Podfile (adjust path as needed)
cd <ios-project-directory>  # e.g., iosApp/, ios/, or project root
pod install
```

### Step 5: Open Workspace

Open `*.xcworkspace` (not .xcodeproj) from the iOS project directory in Xcode.

---

## Getting Help

1. **Check sample projects:**
   - [kmp-with-cocoapods-compose-sample (spm_import branch)](https://github.com/Kotlin/kmp-with-cocoapods-compose-sample/tree/spm_import)
   - [kmp-with-cocoapods-firebase-sample (spm_import branch)](https://github.com/Kotlin/kmp-with-cocoapods-firebase-sample/tree/spm_import)

2. **Generic SPM diagnostics** (verbose build, inspecting generated `KotlinMultiplatformLinkedPackage/`, klib inspection): see the `kotlin-tooling-spm-dependencies` skill's troubleshooting § "Getting Help".
