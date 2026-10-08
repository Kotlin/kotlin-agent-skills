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

### Expected API Didn't Show Up (importedClangModules)

**Symptom:** `Unresolved reference` for classes you expect from an SPM package, even though the import
namespace is correct and the product is listed in `products`.

**Background:** By default (`discoverClangModulesImplicitly = true`) the Clang modules of the declared
products are discovered automatically and cinterop bindings are generated for them. Cinterop runs in
a lenient mode that skips Clang modules that cannot be imported (for example, transitive C/C++
modules), so no extra configuration is normally needed — including for Firebase. Do **not** set
`discoverClangModulesImplicitly = false` or `importedClangModules` preemptively.

**Why `importedClangModules` could still be needed:** It exists as a workaround for the rare case
where automatic discovery doesn't expose the expected API, for example when the SPM product name
differs from the Clang module that actually contains the Objective-C headers (e.g., the
`FirebaseFirestore` product exposes its headers through the `FirebaseFirestoreInternal` Clang module).

**Solution:** Only if the expected API is missing after checking the import namespace (see "Import
Not Found" above):

1. Find the Clang module that contains the missing headers (look at the package's `module.modulemap`
   files or its public headers in the SPM checkout).
2. Disable implicit discovery and list the modules explicitly with the typed API. Since implicit
   discovery is off, list **every** Clang module you need:

```kotlin
swiftPMDependencies {
    discoverClangModulesImplicitly = false

    swiftPackage(
        url = url("https://github.com/firebase/firebase-ios-sdk.git"),
        version = from("12.6.0"),
        products = listOf(product("FirebaseFirestore")),
        importedClangModules = listOf("FirebaseFirestoreInternal"),
    )
}
```

If automatic discovery fails for a package you know well, consider reporting it to the Kotlin team
rather than relying on this workaround permanently.

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

If Firebase classes such as `FIRDatabase`, `FIRRemoteConfig`, `FIRFirestore`, or `FIRInAppMessaging`
are unresolved, see "Expected API Didn't Show Up (importedClangModules)" above. Some Firebase products
expose their headers through `*Internal` Clang modules (`FirebaseDatabaseInternal`,
`FirebaseFirestoreInternal`, `FirebaseInAppMessagingInternal`, `FirebaseRemoteConfigInternal`).

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

# Find the KMP module (Gradle project path without the leading colon) that produces the framework
# for Xcode: either declares embedAndSign*AppleFrameworkForXcode or the Swift Export
# embedSwiftExportForXcode task
KMP_MODULE=$(./gradlew tasks --all --console=plain -q \
  | grep -E 'embedAndSign.*AppleFrameworkForXcode|embedSwiftExportForXcode' \
  | head -1 | awk '{print $1}' | sed -E 's/^://; s/:?[^:]+$//')

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

4. **Inspect klib contents** using the `klib` tool ([docs](https://kotlinlang.org/docs/native-libraries.html#klib-utility)):
   ```bash
   # Dump all API signatures from a klib
   klib dump-metadata-signatures /path/to/library.klib

   # Search for specific classes
   klib dump-metadata-signatures /path/to/library.klib | grep "ClassName"
   
   # Dump the metadata of all library declarations to the output
   klib dump-metadata /path/to/library.klib

   # Find the generated swiftPMImport klib in build output
   find . -name "*.klib" -path "*swiftPMImport*"
   ```
   This is useful for verifying which classes are available in the swiftPMImport klib.
