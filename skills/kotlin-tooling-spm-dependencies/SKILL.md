---
name: kotlin-tooling-spm-dependencies
description: >
  Add and manage Swift Package Manager dependencies in Gradle-based Kotlin Multiplatform projects using
  the swiftPMDependencies {} DSL — declare swiftPackage()/localSwiftPackage(), transform imports to
  swiftPMImport.*, and wire the Xcode project (integrateEmbedAndSign / integrateLinkagePackage).
  Use when adding SPM dependencies to a KMP module (including a greenfield project with no prior
  native dependencies), or when the user mentions swiftPMDependencies, swiftPackage, swiftPMImport,
  SPM import, or Swift Package Manager in a KMP context. For migrating an existing CocoaPods setup,
  use kotlin-tooling-cocoapods-spm-migration instead.
license: Apache-2.0
metadata:
  author: JetBrains
  version: "1.0.0"
---

# Swift Package Manager Dependencies for KMP

Add and manage Swift Package Manager (SPM) dependencies in a Kotlin Multiplatform module using the
`swiftPMDependencies {}` DSL. The DSL declares SPM packages, generates Kotlin cinterop bindings
(reachable under the `swiftPMImport.*` namespace), and wires the iOS/macOS Xcode project so the SPM
libraries link into the final binary.

> **Migrating from CocoaPods?** This skill covers SPM dependencies in general. If you are removing
> an existing `kotlin("native.cocoapods")` setup, use the **`kotlin-tooling-cocoapods-spm-migration`**
> skill — it builds on this one and adds the CocoaPods-removal specifics (pre-migration analysis,
> deintegration, preserving third-party bundled klibs, migration report).

## Requirements

- **Kotlin**: 2.4.0-Beta2 or later (first public release with `swiftPMDependencies` support, available on Maven Central)
- **Xcode**: 16.4 or 26.0+
- **iOS Deployment Target**: 16.0+ recommended

## When to use

- Adding one or more SPM packages (Firebase, Google Maps, a local Swift package, etc.) to a KMP module
- Setting up SPM dependencies in a **greenfield** KMP project that has no prior native dependencies
- Pinning, updating, or reorganizing existing `swiftPMDependencies {}` declarations

The workflow has four parts:

| Step | Action |
|------|--------|
| 1 | Gradle configuration — `group`, `swiftPMDependencies {}`, framework, opt-ins |
| 2 | Kotlin source — import SPM classes via `swiftPMImport.*` |
| 3 | iOS project integration — `integrateEmbedAndSign` / `integrateLinkagePackage`, sandboxing |
| 4 | Verification — compile, link, build the Xcode project |

---

## Step 1: Gradle Configuration

### 1.1 Add the `group` property

The `group` property is **required** — it forms the namespace for the generated `swiftPMImport.*`
bindings (see Step 2).

```kotlin
group = "org.example.myproject"  // Required for import namespace
```

**Compose Resources warning:** If the project uses Compose Multiplatform resources
(`org.jetbrains.compose` plugin or `compose.resources`), the `group` property is also used as the
namespace for generated resource accessors (e.g., `Res.string.*`, `Res.drawable.*`). If `group`
already exists in `build.gradle.kts`, do **not** change it. If you are adding `group` for the first
time, warn the user that existing Compose resource accessor call sites throughout the project will
change namespace and may need updating.

### 1.2 Add the `swiftPMDependencies {}` block

Declare each SPM package with `swiftPackage()`. See [common-packages.md](references/common-packages.md)
for ready-made declarations of popular libraries (Firebase, Google Maps, Google Sign-In, LoremIpsum)
and [dsl-reference.md](references/dsl-reference.md) for the full DSL.

**Two API forms:** The DSL has a simple string API and a typed API. **Use the simple string API**
for most packages:

```kotlin
swiftPackage(url = "https://github.com/owner/repo.git", version = "1.0.0", products = listOf("ProductName"))
```

The simple API auto-defaults `importedClangModules` to the `products` list. Use the typed API (with
`url()`, `exact()`, `product()` wrappers) only when you need exact version pinning, platform
constraints, or explicit Clang module control. See [dsl-reference.md](references/dsl-reference.md)
for the typed API.

**Key concepts:**
- `products` = SPM product names (controls linking).
- `discoverClangModulesImplicitly` defaults to `true`: bindings are generated automatically for the Clang modules of the declared products, and modules that can't be imported are skipped. Leave it at the default — including for Firebase.
- `importedClangModules` = explicit Clang module list, only consulted when `discoverClangModulesImplicitly = false`. It is a troubleshooting fallback for when the expected API doesn't show up; see [troubleshooting.md](references/troubleshooting.md) § "Expected API Didn't Show Up".

**Note:** SPM product names and Clang module names don't always match (e.g., `FirebaseFirestore`
→ `FirebaseFirestoreInternal`). Automatic discovery handles this; see
[common-packages.md](references/common-packages.md) for known mappings if you need to fall back to
explicit `importedClangModules`.

```kotlin
kotlin {
    iosArm64()
    iosSimulatorArm64()
    iosX64()

    swiftPMDependencies {
        iosMinimumDeploymentTarget = "16.0"

        swiftPackage(
            url = "https://github.com/owner/repo.git",
            version = "1.0.0",
            products = listOf("ProductName"),
        )
    }
}
```

### 1.3 Configure the framework

Expose the KMP module to iOS as a framework via the `binaries` API on each target. **`isStatic = true`
is recommended** — dynamic frameworks have known edge cases with SwiftPM import that can cause linker
errors, dyld crashes, or duplicate class warnings (especially with static SPM libraries such as
Firebase):

```kotlin
listOf(iosArm64(), iosSimulatorArm64(), iosX64()).forEach { iosTarget ->
    iosTarget.binaries.framework { baseName = "Shared"; isStatic = true }
}
```

For multi-module projects where the framework must export child modules, add `export(project(...))`
or `transitiveExport = true` to the `binaries.framework {}` block.

### 1.4 Add opt-in annotations

The `swiftPackage()` and `localSwiftPackage()` DSL functions are annotated with
`@ExperimentalKotlinGradlePluginApi`. Add this opt-in at the top of each `build.gradle.kts` that
calls them:

```kotlin
@file:OptIn(org.jetbrains.kotlin.gradle.ExperimentalKotlinGradlePluginApi::class)
```

Also add the cinterop opt-in for Kotlin source files:

```kotlin
kotlin.compilerOptions {
    optIn.add("kotlinx.cinterop.ExperimentalForeignApi")
}
```

For the full DSL reference, see [dsl-reference.md](references/dsl-reference.md).

---

## Step 2: Kotlin Source — Imports

### Import Namespace Formula

```
swiftPMImport.<group>.<module>.<ClassName>

Where:
- group: build.gradle.kts `group` property of the MODULE THAT DECLARES the swiftPMDependencies, dashes (-) → dots (.)
- module: Gradle module name of the MODULE THAT DECLARES the swiftPMDependencies, dashes (-) → dots (.), underscores (_) preserved as-is
- ClassName: Objective-C class name (FIR* for Firebase, GMS* for Google Maps)
```

**The namespace uses the declaring module's group+name, not the importing module's.** This is the
most common mistake. When module A depends on module B, and module B declares `swiftPMDependencies`,
module A imports SPM classes using module B's group and module name — NOT module A's, because that's
where the cinterop bindings are generated.

### Example — Single Module

```kotlin
// group = "org.jetbrains.kotlin.firebase.sample", module = "kotlin-library"

import swiftPMImport.org.jetbrains.kotlin.firebase.sample.kotlin.library.FIRAnalytics
```

### Example — Multi-Module

When `composeApp` depends on a `:google-maps` Gradle module that declares `swiftPMDependencies` with
`GoogleMaps` (`group = "org.jetbrains.kotlin.google-maps"`, module name `google-maps`):

```kotlin
// composeApp/App.kt — uses the google-maps module's namespace, NOT composeApp's:
import swiftPMImport.org.jetbrains.kotlin.google.maps.google.maps.GMSServices
//                    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ ^^^^^^^^^^
//                    google-maps's group (dashes→dots)  google-maps's module name (dashes→dots)
```

### Import flattening

The Clang module name (e.g., `FirebaseFirestoreInternal`, `FirebaseAuth`) disappears from the import
path — all classes are flattened under the same `swiftPMImport.<group>.<module>` prefix regardless of
which library they come from. For example, classes from both `FirebaseAuth` and
`FirebaseFirestoreInternal` become `swiftPMImport.<group>.<module>.FIRAuth` and
`swiftPMImport.<group>.<module>.FIRFirestore`.

**Finding the correct import path:** Run `./gradlew :moduleName:compileKotlinIosSimulatorArm64` —
error messages list the available classes.

---

## Step 3: iOS Project Integration

The KMP framework must be embedded into the Xcode app, and the SPM libraries must be linked into the
final binary. Two Gradle tasks set this up:

- `integrateEmbedAndSign` — modifies the `.xcodeproj` to trigger `embedAndSignAppleFrameworkForXcode` during the Xcode build (adds/configures the "Compile Kotlin" build phase).
- `integrateLinkagePackage` — generates `KotlinMultiplatformLinkedPackage/` (a local Swift package mirroring your `products` list) so SPM libraries link into the final binary. One-time setup; not a build phase.

### 3.1 Run the integration tasks

Discover the paths and run both tasks directly:

```bash
# Find the iOS app directory (the one containing the app .xcodeproj)
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

**Verify `embedAndSignAppleFrameworkForXcode` is active:** After running integration, check the
build phase script in `project.pbxproj`. If `embedAndSignAppleFrameworkForXcode` is commented out
(prefixed with `#`), uncomment it.

### 3.2 Disable User Script Sandboxing

Xcode 16+ enables User Script Sandboxing by default, which prevents the Gradle build phase from
writing to the project directory. Set `ENABLE_USER_SCRIPT_SANDBOXING = NO`:

```bash
sed -i '' 's/ENABLE_USER_SCRIPT_SANDBOXING = YES/ENABLE_USER_SCRIPT_SANDBOXING = NO/g' "$XCODEPROJ/project.pbxproj"
```

If the setting is absent (Xcode defaults to YES), add `ENABLE_USER_SCRIPT_SANDBOXING = NO;` to the
app target's `buildSettings` sections. Then restart the Gradle daemon: `./gradlew --stop`

### 3.3 Manual integration (if automatic fails)

If the integration tasks fail, set up the Xcode project manually — see
[troubleshooting.md](references/troubleshooting.md) § "Manual Xcode Integration Steps" (build phase
ordering, sandboxing, linkage package).

---

## Step 4: Verification

Verify in increasing order of scope. **Do not stop until the application builds successfully** — if
a step fails, diagnose with [troubleshooting.md](references/troubleshooting.md), fix, and re-run.

### 4.1 Compile Kotlin code

```bash
./gradlew :moduleName:compileKotlinIosSimulatorArm64
```

If compilation fails with unresolved references, check the import transformations (Step 2) and the
SwiftPM dependency declarations (Step 1.2). If the expected API is still missing, see
[troubleshooting.md](references/troubleshooting.md) § "Expected API Didn't Show Up"
(`importedClangModules` fallback).

### 4.2 Link the framework

```bash
./gradlew :moduleName:linkDebugFrameworkIosSimulatorArm64
```

Linking errors about missing symbols often mean a product was omitted from `swiftPMDependencies` or a
version constraint resolved to a build with a different API.

### 4.3 Build the iOS/macOS Xcode project

```bash
cd /path/to/iosApp
xcodebuild -project *.xcodeproj -list -json 2>/dev/null | python3 -c "import sys,json; [print(s) for s in json.load(sys.stdin)['project']['schemes']]"
xcodebuild -project *.xcodeproj -scheme "<AppScheme>" -destination 'generic/platform=iOS Simulator' ARCHS=arm64 build
```

**If `checkSandboxAndWriteProtection` fails** — sandboxing was not disabled. Apply the fix from
Step 3.2 and retry.

---

## Additional Resources

- [DSL Reference](references/dsl-reference.md) — full `swiftPMDependencies` syntax
- [Common Packages](references/common-packages.md) — ready-made declarations for popular SPM libraries
- [Troubleshooting](references/troubleshooting.md) — common issues and solutions
