# Common SPM Packages for KMP

Ready-made `swiftPackage()` declarations for popular Swift Package Manager dependencies, plus the
Clang-module-name quirks and iOS-project requirements each one needs. The "CocoaPods pod" notes are
provided as a cross-reference for readers arriving from `kotlin-tooling-cocoapods-spm-migration`.

## Firebase Suite

All Firebase products come from a single repository: `https://github.com/firebase/firebase-ios-sdk.git`

**Key facts:**
- Exception: Beta products have a `-Beta` suffix in SPM (e.g., `FirebaseAppDistribution-Beta`)
- The CocoaPods umbrella pod `Firebase` does not exist in SPM — import specific products
- **Platform requirements**: iOS 15+, macOS 10.15+, tvOS 15+, watchOS 7+
- **Xcode**: 16.2+

> **WARNING: Use one package manager for the whole Firebase suite.** All Firebase products share a single repository and common transitive dependencies (gRPC, abseil, leveldb, BoringSSL, nanopb, etc.). If some Firebase products are linked via SPM while others come from a different package manager (e.g., leftover CocoaPods), the shared transitive dependencies get linked twice with conflicting symbols, causing **dyld crashes at runtime** (e.g., `Symbol not found: _OBJC_CLASS_$_FIRFirestore`). Declare **all** Firebase products you need via SPM at once — including Swift-only products (FirebaseAI, FirebaseFunctions, FirebaseMLModelDownloader). Add Swift-only products as `products` entries without `importedClangModules`. After adding new products, re-run `integrateLinkagePackage` to regenerate the linkage Swift package.

### Firebase SPM Products Reference

| SPM Product | Platform | KMP Notes |
|-------------|----------|-----------|
| FirebaseAnalytics | All | ObjC classes: `FIRAnalytics`, `FIRApp` |
| FirebaseAuth | All (partial on macOS/tvOS/watchOS) | ObjC classes: `FIRAuth`, `FIRUser` |
| FirebaseCore | All | ObjC class: `FIRApp` |
| FirebaseCrashlytics | All | ObjC class: `FIRCrashlytics` |
| FirebaseDatabase | All | **importedClangModules: `FirebaseDatabaseInternal`** — ObjC classes: `FIRDatabase`, `FIRDatabaseReference` |
| FirebaseFirestore | All | **Special case** — see below |
| FirebaseFunctions | All | Swift-only — no `importedClangModules` entry needed |
| FirebaseMessaging | All | ObjC classes: `FIRMessaging` |
| FirebaseRemoteConfig | All | **importedClangModules: `FirebaseRemoteConfigInternal`** — ObjC class: `FIRRemoteConfig` |
| FirebaseStorage | All | ObjC class: `FIRStorage` |
| FirebaseAppCheck | All (watchOS 9+) | ObjC class: `FIRAppCheck` |
| FirebasePerformance | iOS/tvOS only | ObjC class: `FIRPerformance` |
| FirebaseInAppMessaging-Beta | iOS/tvOS only | `-Beta` suffix in SPM, **importedClangModules: `FirebaseInAppMessagingInternal`** |
| FirebaseAppDistribution-Beta | iOS only | `-Beta` suffix in SPM |
| FirebaseInstallations | All | ObjC class: `FIRInstallations` |
| FirebaseABTesting | All | **Module-only**: pulled transitively by RemoteConfig. List in `importedClangModules` only, no product |
| FirebaseAI | All | (CocoaPods pod `FirebaseAILogic`) — **renamed in SPM**. Swift-only — no `importedClangModules` entry needed |
| FirebaseMLModelDownloader | All | Swift-only — no `importedClangModules` entry needed |

### FirebaseAnalytics

```kotlin
swiftPackage(
    url = "https://github.com/firebase/firebase-ios-sdk.git",
    version = "12.5.0",
    products = listOf("FirebaseAnalytics"),
)
```

**Kotlin import:**
```kotlin
import swiftPMImport.<group>.<module>.FIRAnalytics
import swiftPMImport.<group>.<module>.FIRApp
```

### FirebaseAuth

```kotlin
swiftPackage(
    url = "https://github.com/firebase/firebase-ios-sdk.git",
    version = "12.5.0",
    products = listOf("FirebaseAuth"),
)
```

**Kotlin import:**
```kotlin
import swiftPMImport.<group>.<module>.FIRAuth
import swiftPMImport.<group>.<module>.FIRUser
```

### FirebaseDatabase

Database's Clang module name differs from its SPM product name. You **must** specify `importedClangModules` (requires typed API):

```kotlin
swiftPackage(
    url = url("https://github.com/firebase/firebase-ios-sdk.git"),
    version = from("12.5.0"),
    products = listOf(product("FirebaseDatabase")),
    importedClangModules = listOf("FirebaseDatabaseInternal"),
)
```

**Kotlin import:**
```kotlin
import swiftPMImport.<group>.<module>.FIRDatabase
import swiftPMImport.<group>.<module>.FIRDatabaseReference
```

### FirebaseFirestore (Special Case)

Firestore's Clang module name differs from its SPM product name. You **must** specify `importedClangModules` (requires typed API):

```kotlin
swiftPackage(
    url = url("https://github.com/firebase/firebase-ios-sdk.git"),
    version = from("12.5.0"),
    products = listOf(product("FirebaseFirestore")),
    importedClangModules = listOf("FirebaseFirestoreInternal"),
)
```

**Kotlin import:**
```kotlin
import swiftPMImport.<group>.<module>.FIRFirestore
import swiftPMImport.<group>.<module>.FIRDocumentReference
```

**Why is this needed?** Firestore distributes as a binary xcframework. The internal Clang module exposed to Objective-C is named `FirebaseFirestoreInternal`, not `FirebaseFirestore`. Without `importedClangModules`, the KMP compiler cannot discover the Objective-C headers.

### FirebaseCrashlytics

```kotlin
swiftPackage(
    url = "https://github.com/firebase/firebase-ios-sdk.git",
    version = "12.5.0",
    products = listOf("FirebaseCrashlytics"),
)
```

**iOS project requirement:** Crashlytics needs a dSYM upload run script in the Xcode build phases. Add a "Run Script" phase at the END of build phases:

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

Also set **Debug Information Format** to `DWARF with dSYM File` for all build configurations.

### Combined Firebase Example

When using multiple Firebase products, declare them in a single package. **Set `discoverClangModulesImplicitly = false`** — Firebase's transitive C++ dependencies (gRPC, abseil, leveldb, BoringSSL) contain Clang modules that fail cinterop. Explicitly list only the modules you need.

```kotlin
swiftPMDependencies {
    discoverClangModulesImplicitly = false

    // Combined Firebase requires typed API for importedClangModules control
    swiftPackage(
        url = url("https://github.com/firebase/firebase-ios-sdk.git"),
        version = from("12.5.0"),
        products = listOf(
            product("FirebaseAnalytics"),
            product("FirebaseAuth"),
            product("FirebaseDatabase"),
            product("FirebaseFirestore"),
            product("FirebaseCrashlytics"),
            product("FirebaseMessaging"),
            product("FirebaseRemoteConfig"),
            // Swift-only products (products only, no importedClangModules):
            product("FirebaseAI"),
            product("FirebaseFunctions"),
        ),
        importedClangModules = listOf(
            "FirebaseAnalytics",
            "FirebaseAuth",
            "FirebaseCore",
            "FirebaseCrashlytics",
            "FirebaseDatabaseInternal",      // Not "FirebaseDatabase"
            "FirebaseFirestoreInternal",     // Not "FirebaseFirestore"
            "FirebaseMessaging",
            "FirebaseRemoteConfigInternal",  // Not "FirebaseRemoteConfig"
            "FirebaseABTesting",             // Module-only, no product
        ),
    )
}
```

### Firebase importedClangModules Reference

Several Firebase products expose ObjC headers through Clang modules whose names differ from the SPM product name:

| SPM Product | Clang Module (importedClangModules) | Notes |
|---|---|---|
| FirebaseAnalytics | FirebaseAnalytics | Same name |
| FirebaseAuth | FirebaseAuth | Same name |
| FirebaseCore | FirebaseCore | Same name |
| FirebaseCrashlytics | FirebaseCrashlytics | Same name |
| FirebaseDatabase | **FirebaseDatabaseInternal** | Different |
| FirebaseFirestore | **FirebaseFirestoreInternal** | Different |
| FirebaseInAppMessaging-Beta | **FirebaseInAppMessagingInternal** | Different |
| FirebaseRemoteConfig | **FirebaseRemoteConfigInternal** | Different |
| FirebaseInstallations | FirebaseInstallations | Same name |
| FirebaseMessaging | FirebaseMessaging | Same name |
| FirebasePerformance | FirebasePerformance | Same name |
| FirebaseStorage | FirebaseStorage | Same name |
| FirebaseAppCheck | FirebaseAppCheck | Same name |
| FirebaseAppDistribution-Beta | FirebaseAppDistribution | Same name (no `-Beta`) |
| *(transitive)* | **FirebaseABTesting** | Module-only, no product |
| FirebaseAI | *(none)* | Swift-only, no cinterop |
| FirebaseFunctions | *(none)* | Swift-only, no cinterop |
| FirebaseMLModelDownloader | *(none)* | Swift-only, no cinterop |

**Note:** When `discoverClangModulesImplicitly = false` (recommended for Firebase), you must list every Clang module you import in `importedClangModules`. When `true` (default), `importedClangModules` is ignored — but this will fail for Firebase due to C++ transitive dependencies.

### Firebase: Static Framework Required

Firebase SPM products are **static** libraries — their `.framework` bundles exist in
`$BUILT_PRODUCTS_DIR` during build but are NOT embedded in the app bundle. If the KMP framework is
**dynamic** (`isStatic = false` or default), the Kotlin/Native linker creates
`@rpath/FirebaseCore.framework/FirebaseCore` load instructions and the app crashes at launch with
`dyld: Library not loaded`. Use `isStatic = true` so all symbols are embedded and unresolved
framework flags are deferred to the final Xcode app link.

### Firebase Initialization

Ensure `GoogleService-Info.plist` is included in the iOS app target. In the app's entry point:

```swift
import Firebase
FirebaseApp.configure()  // Must be called before using any Firebase service
```

---

## Google Maps

Repository: `https://github.com/googlemaps/ios-maps-sdk.git`

**Key facts:**
- **iOS 16+ only** — no macOS, tvOS, or watchOS support
- **Xcode 16.0+** required
- Must use `exact()` version — `from()` will fail to resolve
- Single SPM product: `GoogleMaps` (wraps a binary xcframework via `GoogleMapsTarget`)
- CocoaPods subspec `GoogleMaps/Maps` maps to the single `GoogleMaps` SPM product
- Requires a Google Maps Platform API key configured in the iOS app
- Check [releases](https://github.com/googlemaps/ios-maps-sdk/releases) for available SPM versions

```kotlin
swiftPackage(
    url = url("https://github.com/googlemaps/ios-maps-sdk.git"),
    version = exact("10.10.0"),  // Must use exact(), not from()
    products = listOf(
        product("GoogleMaps", platforms = setOf(iOS()))
    ),
)
```

**Kotlin import:**
```kotlin
import swiftPMImport.<group>.<module>.GMSMapView
import swiftPMImport.<group>.<module>.GMSCameraPosition
import swiftPMImport.<group>.<module>.GMSMarker
import swiftPMImport.<group>.<module>.GMSServices
```

**iOS project requirement:** The API key must be set in the app delegate or SwiftUI app entry point:

```swift
import GoogleMaps
GMSServices.provideAPIKey("YOUR_API_KEY")
```

---

## Google Sign-In

Repository: `https://github.com/google/GoogleSignIn-iOS.git`

**Key facts:**
- **iOS 12+, macOS 10.15+** — broad platform support
- Two SPM products: `GoogleSignIn` (core) and `GoogleSignInSwift` (SwiftUI support)
- CocoaPods pods: `GoogleSignIn` and `GoogleSignInSwiftSupport`
- Uses `from()` versioning (latest: 9.1.0)

```kotlin
swiftPackage(
    url = "https://github.com/google/GoogleSignIn-iOS.git",
    version = "8.0.0",
    products = listOf("GoogleSignIn"),
)
```

**Kotlin import:**
```kotlin
import swiftPMImport.<group>.<module>.GIDSignIn
import swiftPMImport.<group>.<module>.GIDSignInButton
```

**iOS project requirement:** Add `GIDClientID` to `Info.plist` and configure the URL scheme for OAuth redirect. See [Google Sign-In iOS docs](https://developers.google.com/identity/sign-in/ios/start-integrating).

---

## LoremIpsum

Simple text generation library with direct mapping.

```kotlin
swiftPackage(
    url = "https://github.com/lukaskubanek/LoremIpsum.git",
    version = "2.0.1",
    products = listOf("LoremIpsum"),
)
```

**Kotlin import:**
```kotlin
import swiftPMImport.<group>.<module>.LoremIpsum
```

---

## Quick Reference Table

| SPM Product | SPM Repository | Version Type | Platform | Notes |
|-------------|----------------|--------------|----------|-------|
| FirebaseAnalytics | firebase/firebase-ios-sdk.git | from() | All | |
| FirebaseAuth | firebase/firebase-ios-sdk.git | from() | All | |
| FirebaseCore | firebase/firebase-ios-sdk.git | from() | All | |
| FirebaseCrashlytics | firebase/firebase-ios-sdk.git | from() | All | Needs dSYM upload script |
| FirebaseDatabase | firebase/firebase-ios-sdk.git | from() | All | importedClangModules: FirebaseDatabaseInternal |
| FirebaseFirestore | firebase/firebase-ios-sdk.git | from() | All | importedClangModules: FirebaseFirestoreInternal |
| FirebaseFunctions | firebase/firebase-ios-sdk.git | from() | All | Swift-only, no cinterop |
| FirebaseMessaging | firebase/firebase-ios-sdk.git | from() | All | |
| FirebaseRemoteConfig | firebase/firebase-ios-sdk.git | from() | All | importedClangModules: FirebaseRemoteConfigInternal |
| FirebaseStorage | firebase/firebase-ios-sdk.git | from() | All | |
| FirebasePerformance | firebase/firebase-ios-sdk.git | from() | iOS/tvOS | |
| FirebaseInAppMessaging-Beta | firebase/firebase-ios-sdk.git | from() | iOS/tvOS | `-Beta` suffix, importedClangModules: FirebaseInAppMessagingInternal |
| FirebaseAppDistribution-Beta | firebase/firebase-ios-sdk.git | from() | iOS only | `-Beta` suffix |
| FirebaseABTesting | firebase/firebase-ios-sdk.git | — | All | Module-only, importedClangModules only |
| FirebaseAI | firebase/firebase-ios-sdk.git | from() | All | (pod `FirebaseAILogic`) renamed, Swift-only |
| GoogleMaps | googlemaps/ios-maps-sdk.git | exact() | iOS 16+ only | |
| GoogleSignIn | google/GoogleSignIn-iOS.git | from() | iOS 12+, macOS 10.15+ | |
| GoogleSignInSwift | google/GoogleSignIn-iOS.git | from() | iOS 12+, macOS 10.15+ | SwiftUI support (pod `GoogleSignInSwiftSupport`) |
| LoremIpsum | lukaskubanek/LoremIpsum.git | from() | All | |

---

## Researching Other Packages

For packages not listed here:

1. **Check GitHub repository** - Look for a `Package.swift` file in the repo
2. **Check CocoaPods spec** (if migrating) - The `source` field often points to the Git URL
3. **Search Swift Package Index** - https://swiftpackageindex.com/
4. **Check library documentation** - Many libraries document SPM installation

### Finding the Clang Module Name

If you're unsure of the correct Clang module name:

1. Keep `discoverClangModulesImplicitly = true` (default)
2. Run `./gradlew build`
3. Check build errors for available class names
4. Or check the library's `module.modulemap` file in its source
