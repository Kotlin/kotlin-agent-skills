# Troubleshooting Guide

Common issues and solutions when using `swiftPMDependencies {}` in a KMP project.

## Gradle Issues

### Import Not Found

**Symptom:** `Unresolved reference` errors for classes from an SPM package

**Solution:** The import namespace follows a specific pattern:

```
swiftPMImport.<group>.<module>.<ClassName>
```

**Steps to fix:**
1. Check the `group` property in `build.gradle.kts`
2. Replace `-` with `.` in both group and module names
3. Run `./gradlew build` to see available classes in error messages

**Example:**
```kotlin
// If group = "org.jetbrains.kotlin.firebase-sample" and module = "kotlin-library"
// Import becomes:
import swiftPMImport.org.jetbrains.kotlin.firebase.sample.kotlin.library.FIRAnalytics
//                    ^                          ^      ^
//                    dashes become dots --------+------+
```

Remember: in a multi-module project the namespace uses the **declaring** module's group and name
(the module with the `swiftPMDependencies {}` block), not the importing module's.

---

### Gradle Sync Fails

**Symptom:** IDE fails to sync project after adding swiftPMDependencies

**Solution:**
1. Invalidate caches: File > Invalidate Caches > Invalidate and Restart
2. Run `./gradlew --refresh-dependencies`
3. Confirm the Kotlin version is 2.4.0-Beta2 or later (the first release with `swiftPMDependencies`)

---

## Linker Issues

### Missing Symbols / Linker Errors

**Symptom:** `Undefined symbols for architecture` errors

**Solutions:**

1. **Run the linkage integration task** (one-time, not a build phase):
   ```bash
   ./gradlew :moduleName:integrateLinkagePackage
   ```

2. **Verify SPM package is linked in Xcode:**
   - Open project in Xcode
   - Check Package Dependencies section
   - Ensure `KotlinMultiplatformLinkedPackage` is present

3. **Check framework configuration** — `isStatic = true` is recommended. While `isStatic = false` can work, dynamic frameworks have known edge cases with SwiftPM import (linker errors, dyld crashes, duplicate class warnings), especially with static SPM libraries like Firebase.

---

### "No such module" in Xcode

**Symptom:** Xcode can't find the Kotlin module

**Solution:**
1. Clean Xcode build folder: Shift+Cmd+K
2. Re-run integration:
   ```bash
   ./gradlew :moduleName:integrateLinkagePackage
   ```
3. Restart Xcode completely
4. Re-open the correct Xcode project file

---

## Build Phase Issues

### Build Phase Order Problems

**Symptom:** Swift compilation fails because Kotlin framework isn't ready

**Solution:** Ensure "Compile Kotlin" runs BEFORE "Compile Sources":

1. Open Xcode project
2. Select app target > Build Phases
3. Drag "Compile Kotlin" phase above "Compile Sources"

---

### Script Sandboxing Errors

**Symptom:** Gradle task `checkSandboxAndWriteProtection` fails during Xcode build:

```
Execution failed for task ':moduleName:checkSandboxAndWriteProtection'.
> User Script Sandboxing Enabled in Xcode Project
```

Or build scripts can't access files or run Gradle.

**Cause:** Xcode 16+ enables User Script Sandboxing by default. The Gradle build phase needs to write to the project directory, which sandboxing prevents.

**Solution:**

1. Disable via command line:
   ```bash
   sed -i '' 's/ENABLE_USER_SCRIPT_SANDBOXING = YES/ENABLE_USER_SCRIPT_SANDBOXING = NO/g' /path/to/iosApp/*.xcodeproj/project.pbxproj
   ```
   If the setting is not present in the `.pbxproj` (Xcode defaults to YES without an explicit entry), open the project in Xcode instead.

2. Or disable in Xcode: select app target → Build Settings → Build Options → set "User Script Sandboxing" to NO

3. **Important:** After changing the setting, stop the Gradle daemon:
   ```bash
   ./gradlew --stop
   ```

---

## Firebase-Specific Issues

### cinterop Failures on C++ Modules (gRPC, abseil, leveldb, BoringSSL)

**Symptom:** Build fails with cinterop errors on modules like `grpc`, `absl`, `leveldb`, `openssl_grpc`, or other C++ transitive dependencies of Firebase.

**Cause:** `discoverClangModulesImplicitly = true` (the default) makes Kotlin attempt cinterop on every Clang module in the dependency graph, including C++ modules that are not compatible.

**Solution:** Set `discoverClangModulesImplicitly = false` and explicitly list only the Firebase Clang modules you need:

```kotlin
swiftPMDependencies {
    discoverClangModulesImplicitly = false

    swiftPackage(
        url = url("https://github.com/firebase/firebase-ios-sdk.git"),
        version = from("12.6.0"),
        products = listOf(product("FirebaseAnalytics"), /* ... */),
        importedClangModules = listOf("FirebaseAnalytics", "FirebaseCore", /* ... */),
    )
}
```

See [common-packages.md](common-packages.md) for the full importedClangModules reference.

---

### Firebase Classes Not Found (Wrong Clang Module Name)

**Symptom:** `Unresolved reference` for Firebase classes like `FIRDatabase`, `FIRRemoteConfig`, `FIRFirestore`, `FIRInAppMessaging` even though the product is listed.

**Cause:** Several Firebase products expose ObjC headers through Clang modules whose names differ from the SPM product name. Using the product name in `importedClangModules` won't find the headers.

**Solution:** Use the correct internal Clang module names:

| SPM Product | Correct importedClangModules entry |
|---|---|
| FirebaseDatabase | `FirebaseDatabaseInternal` |
| FirebaseFirestore | `FirebaseFirestoreInternal` |
| FirebaseInAppMessaging-Beta | `FirebaseInAppMessagingInternal` |
| FirebaseRemoteConfig | `FirebaseRemoteConfigInternal` |

---

### FirebaseFirestore Import Errors

**Symptom:** Can't import FIRFirestore classes

**Cause:** Firestore's Clang module name differs from product name. The internal Clang module exposed to Objective-C is `FirebaseFirestoreInternal`, not `FirebaseFirestore`.

**Solution:** Add explicit importedClangModules:

```kotlin
swiftPackage(
    url = url("https://github.com/firebase/firebase-ios-sdk.git"),
    version = from("12.6.0"),
    products = listOf(product("FirebaseFirestore")),
    importedClangModules = listOf("FirebaseFirestoreInternal"),  // Required
)
```

---

### Firebase Crashlytics: dSYM Upload Script

**Symptom:** Crash reports don't appear in Firebase Console. Or the build phase fails with "No such file" errors referencing a dSYM upload script.

**Solution:** Add (or fix) a "Run Script" build phase at the END of build phases:

```bash
"${BUILD_DIR%/Build/*}/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run"
```

With input files:
```
${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}
${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}/Contents/Resources/DWARF/${PRODUCT_NAME}
${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}/Contents/Info.plist
$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/GoogleService-Info.plist
$(TARGET_BUILD_DIR)/$(EXECUTABLE_PATH)
```

Also set **Debug Information Format** to `DWARF with dSYM File` for all build configurations in Build Settings.

---

### Firebase Beta Products: SPM Name Differs

**Symptom:** `FirebaseInAppMessaging` or `FirebaseAppDistribution` not found as SPM product

**Cause:** Beta products have a `-Beta` suffix in SPM.

**Solution:** Use the correct SPM product name:
- `FirebaseInAppMessaging` → `FirebaseInAppMessaging-Beta`
- `FirebaseAppDistribution` → `FirebaseAppDistribution-Beta`

---

### Firebase Initialization Fails at Runtime

**Symptom:** App crashes on Firebase initialization

**Solution:**
1. Ensure `GoogleService-Info.plist` is in iOS app target
2. Call `FIRApp.configure()` before using any Firebase service
3. Check Firebase console for configuration issues

---

## Google Maps Issues

### GoogleMaps Version Not Found

**Symptom:** SPM can't resolve GoogleMaps package

**Solution:** GoogleMaps requires exact version matching:

```kotlin
swiftPackage(
    url = url("https://github.com/googlemaps/ios-maps-sdk.git"),
    version = exact("10.6.0"),  // Must use exact(), not from()
    products = listOf(
        product("GoogleMaps", platforms = setOf(iOS()))
    ),
)
```

Check [releases page](https://github.com/googlemaps/ios-maps-sdk/releases) for valid versions.

---

## KSP (Kotlin Symbol Processing) Compatibility

KSP should generally work with the target Kotlin version without any changes. If KSP fails after
changing the Kotlin version, the issue is unrelated to SwiftPM dependencies — present the error to
the user and handle it separately.

---

## Manual Integration Command Discovery

If the integration tasks need to be run manually, discover the paths and run the tasks directly:

```bash
# Find the iOS app directory (contains the app .xcodeproj)
XCODEPROJ=$(realpath "$(find . -maxdepth 3 -name "*.xcodeproj" -type d | grep -v Pods | head -1)")

# Find KMP module with swiftPMDependencies (module directory name)
KMP_MODULE=$(grep -rl "swiftPMDependencies" --include="build.gradle.kts" . | head -1 | xargs dirname | xargs basename)

XCODEPROJ_PATH="$XCODEPROJ" \
GRADLE_PROJECT_PATH=":$KMP_MODULE" \
./gradlew ":$KMP_MODULE:integrateEmbedAndSign" ":$KMP_MODULE:integrateLinkagePackage"
```

---

## Manual Xcode Integration Steps

If the automatic `integrateEmbedAndSign` / `integrateLinkagePackage` tasks fail, set up the Xcode project manually:

1. Open `.xcodeproj` (or `.xcworkspace` if it exists)
2. Add "Compile Kotlin" run script phase BEFORE "Compile Sources":
   ```bash
   cd "$SRCROOT/.."
   ./gradlew :moduleName:embedAndSignAppleFrameworkForXcode
   ```
3. Set `ENABLE_USER_SCRIPT_SANDBOXING = NO` (Build Settings → Build Options → User Script Sandboxing)
4. Run `./gradlew --stop` to restart the Gradle daemon after changing sandboxing
5. Add local package: `../moduleName/KotlinMultiplatformLinkedPackage`

---

## Getting Help

If issues persist:

1. **Check sample projects:**
   - [kmp-with-cocoapods-compose-sample (spm_import branch)](https://github.com/Kotlin/kmp-with-cocoapods-compose-sample/tree/spm_import)
   - [kmp-with-cocoapods-firebase-sample (spm_import branch)](https://github.com/Kotlin/kmp-with-cocoapods-firebase-sample/tree/spm_import)

2. **Run verbose build:**
   ```bash
   ./gradlew build --info
   ```

3. **Check generated files:**
   - Look in `moduleName/KotlinMultiplatformLinkedPackage/` for Package.swift

4. **Inspect klib contents** using the `klib` tool ([docs](https://kotlinlang.org/docs/native-libraries.html#using-kotlin-native-compiler)):
   ```bash
   # Dump all API signatures from a klib
   klib dump-metadata-signatures /path/to/library.klib

   # Search for specific classes
   klib dump-metadata-signatures /path/to/library.klib | grep "ClassName"

   # Find the generated swiftPMImport klib in build output
   find . -name "*.klib" -path "*swiftPMImport*"
   ```
   This is useful for verifying which classes are available in the swiftPMImport klib.
