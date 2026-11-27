#!/usr/bin/env bash
# Inventory of everything that typically changes when migrating a KMP project from
# Objective-C export (+ SKIE / KMP-NativeCoroutines / CocoaPods) to Swift Export.
# Read-only. Usage: scan-objc-export-usages.sh [repo-root] [kotlin-module-dir...]   (default: current directory)
#   kotlin-module-dir: restrict the Kotlin API scans to these dirs (e.g. <SHARED_DIR>; relative to repo-root or
#   absolute). Kotlin API scans always skip source sets that never reach Apple (main/android/jvm/desktop/js/wasm/
#   mingw/linux/... and *Test), so Android/desktop app modules don't show up.
# Never read stdin: a grep whose file list expands to nothing would otherwise wait forever.
exec </dev/null
set -uo pipefail

ROOT="${1:-.}"
[ $# -gt 0 ] && shift
KT_ROOTS=()
for d in "$@"; do case "$d" in /*) KT_ROOTS+=("$d") ;; *) KT_ROOTS+=("$ROOT/$d") ;; esac; done
[ ${#KT_ROOTS[@]} -gt 0 ] || KT_ROOTS=("$ROOT")
SCAN_ROOTS=("$ROOT")
# hits are "path:line:text"; Kotlin source sets that never reach Apple targets
NON_APPLE='^[^:]*/src/(main|test|android|jvm|desktop|js|wasm|mingw|linux|windows|server|androidNative)[A-Za-z0-9]*/|^[^:]*/src/[A-Za-z0-9]*Test/'
PATH_SKIP=""
EXCLUDES=(--exclude-dir=build --exclude-dir=.gradle --exclude-dir=.kotlin --exclude-dir=.git
          --exclude-dir=Pods --exclude-dir=DerivedData --exclude-dir=.build --exclude-dir=node_modules
          --exclude-dir=SwiftPackage --exclude-dir=xcuserdata)
MAX="${MAX_HITS:-40}"

section() { printf '\n=== %s ===\n' "$1"; }
# scan <title> <regex> <include-glob>...
scan() {
  local title="$1" regex="$2"; shift 2
  local includes=()
  for g in "$@"; do includes+=(--include="$g"); done
  local out
  out=$(grep -rnE "${EXCLUDES[@]}" "${includes[@]}" -- "$regex" "${SCAN_ROOTS[@]}" 2>/dev/null)
  if [ -n "$PATH_SKIP" ] && [ -n "$out" ]; then out=$(printf '%s\n' "$out" | grep -vE -- "$PATH_SKIP"); fi
  if [ -n "${SKIP:-}" ] && [ -n "$out" ]; then out=$(printf '%s\n' "$out" | grep -vE -- "$SKIP"); fi
  if [ -n "$out" ]; then
    local n; n=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
    printf -- '--- %s (%s hits)\n' "$title" "$n"
    printf '%s\n' "$out" | head -n "$MAX"
    [ "$n" -gt "$MAX" ] && printf '    ... %s more (MAX_HITS=%s)\n' "$((n - MAX))" "$MAX"
  fi
}

GRADLE=("*.gradle.kts" "*.gradle" "*.toml" "gradle.properties" "gradle-wrapper.properties")
KT=("*.kt")
SWIFT=("*.swift")
XCODE=("*.pbxproj" "*.xcconfig" "Podfile" "Package.swift" "*.xcscheme")

section "Toolchain versions"
scan "Kotlin / KSP / AGP / SKIE / NativeCoroutines versions" '^(kotlin|ksp|agp|android-gradle-plugin|skie|kmp-?nativecoroutines|nativeCoroutines|kotlinx-coroutines|coroutines)[A-Za-z0-9_-]* *=' "*.toml"
scan "Gradle wrapper" 'distributionUrl' "gradle-wrapper.properties"
scan "Plugin versions in build scripts" 'kotlin\("multiplatform"\) version|id\("org.jetbrains.kotlin[^"]*"\) version|co.touchlab.skie|com.rickclephas.kmp.nativecoroutines|com.google.devtools.ksp' "${GRADLE[@]}"

KV=$(grep -hE '^kotlin *= *"' "$ROOT"/gradle/*.toml 2>/dev/null | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
if [ -n "$KV" ]; then
  KVRE=$(printf '%s' "$KV" | sed 's/\./\\./g')
  SKIP='toml:[0-9]+:kotlin *=' scan "Hard-coded Kotlin version $KV outside the catalog entry (must follow the upgrade)" "[\"':]${KVRE}[\"']" "${GRADLE[@]}"
fi

section "Gradle: ObjC export / packaging to replace"
scan "binaries.framework / XCFramework / framework export" 'binaries\.framework|XCFramework|xcframework|transitiveExport|\bexport\((project|projects\.|libs\.)|baseName *=' "${GRADLE[@]}"
scan "CocoaPods" 'native\.cocoapods|cocoapods *\{|pod\(' "${GRADLE[@]}"
scan "SKIE / KMP-NativeCoroutines / packaging plugins" 'skie|nativecoroutines|NativeCoroutines|multiplatform-swiftpackage|multiplatformSwiftPackage|kmmbridge|KMMBridge' "${GRADLE[@]}"
scan "Existing Swift Export config (old swiftExport{} or new export{swift{}})" 'swiftExport|flattenPackage|export *\{|swift *\{|xcodeIntegration|swiftPackageIntegration|ExperimentalSwiftExportDsl' "${GRADLE[@]}"
scan "Deprecated swiftExport { } DSL (must be migrated to export { swift { } } and deleted: gradle-and-xcode.md §1b)" 'swiftExport *\{' "${GRADLE[@]}" "*.kt"
scan "Apple targets" 'ios(X64|Arm64|SimulatorArm64)\(|macos(X64|Arm64)\(|tvos|watchos|applyDefaultHierarchyTemplate' "${GRADLE[@]}"
scan "Compiler plugins that may generate public API (check generated Swift)" 'koin.*compiler|koin-annotations|io.insert-koin.compiler|sqldelight|ksp\(|kspIos|kotlin\("plugin\.serialization"\)|parcelize|kotlinx-rpc|ktorfit' "${GRADLE[@]}"
scan "Free compiler args / export-kdoc" 'freeCompilerArgs|Xexport-kdoc|explicitApi' "${GRADLE[@]}"

section "Kotlin: annotations and ObjC-shaped API (source sets that reach Apple only)"
SCAN_ROOTS=("${KT_ROOTS[@]}"); PATH_SKIP="$NON_APPLE"
NONPUB='^[^:]+:[0-9]+:[[:space:]]*(private|internal|protected)'
scan "KMP-NativeCoroutines annotations" '@NativeCoroutines|@NativeCoroutinesState|@NativeCoroutineScope|@NativeCoroutinesIgnore|@NativeCoroutinesRefined' "${KT[@]}"
scan "ObjC interop annotations" '@ObjCName|@ShouldRefineInSwift|@HiddenFromObjC|@HidesFromObjC|@Throws' "${KT[@]}"
SKIP="$NONPUB" scan "Mutable collection parameters (not supported by Swift Export: use read-only List/Set/Map)" '(fun|constructor)[^=]*\([^)]*: *(Mutable(List|Set|Map|Collection)|ArrayList|HashMap|HashSet|LinkedHashMap|LinkedHashSet)<' "${KT[@]}"
scan "Classes implementing List/Set/Map/Collection (not instantiable from Swift: wrap)" '(class|object) +[A-Za-z0-9_]+(<[^>]*>)?( *(internal|private|public)? *constructor)? *(\([^)]*\))? *: *([A-Za-z0-9_.<>]+(\([^)]*\))? *, *)*(Abstract|Mutable)?(List|Set|Map|Collection)<' "${KT[@]}"
scan "Kotlin types named like Swift/SwiftUI/Foundation types (ambiguous in Swift files)" '^(public )?(data |sealed |open |abstract |enum |value |fun )?(class|interface|object) (Shape|Color|Text|Image|View|Hasher|Result|Error|Data|Date|URL|Task|Set|Array|Dictionary|Character|Button|Section|Label|Font|Animation|Timer|Notification|Locale|Calendar|Range|Optional|Identifiable|Group|Form|Toggle|Picker|Menu|Link|Path|Angle|Edge|Alignment|Binding|State|Environment|Published|Observable|Codable|UUID|Decimal)\b' "${KT[@]}"
# Parameters of generic classes with concrete type arguments: not exported; inside List/Set/Map they break the build.
generic_params=$(grep -rnE "${EXCLUDES[@]}" --include="*.kt" -- '(fun|constructor)[^=]*\([^)]*: *[A-Z][A-Za-z0-9_.]*<[A-Z]' "${SCAN_ROOTS[@]}" 2>/dev/null \
  | grep -vE -- "$NON_APPLE" | grep -vE "$NONPUB" \
  | grep -E ': *(List|Set|Map|Collection|Iterable)<[^>]*<[A-Z]|: *[A-Z][A-Za-z0-9_.]*<[A-Z]' \
  | grep -vE ': *(List|Set|Map|Collection|Iterable|Flow|StateFlow|SharedFlow|MutableStateFlow|MutableSharedFlow|Array|Pair|Triple|Comparable|KClass|Function[0-9]*|Lazy|Sequence)<[A-Za-z0-9_.?*, ]*>' )
if [ -n "$generic_params" ]; then
  n=$(printf '%s\n' "$generic_params" | wc -l | tr -d ' ')
  printf -- '--- Parameters typed as generic classes with concrete type args (not exported; in List/Set/Map: may break the build) -> references/wrapping-generics.md (%s hits)\n' "$n"
  printf '%s\n' "$generic_params" | head -n "$MAX"
fi
scan "Generic sealed/interface declarations in the API (erased in Swift; consider wrappers)" '^[[:space:]]*(public )?(sealed (class|interface)|interface|open class|abstract class|class|data class) [A-Z][A-Za-z0-9_]*<' "${KT[@]}"
# KT-90088: Kotlin enums as elements of collections / flows of collections crash at runtime in Swift (known-issues.md)
enums=$(grep -rnoE "${EXCLUDES[@]}" --include="*.kt" -- '^[[:space:]]*(public )?enum class [A-Z][A-Za-z0-9_]*' "${SCAN_ROOTS[@]}" 2>/dev/null \
  | grep -vE -- "$NON_APPLE" | sed -E 's/.*enum class //' | sort -u | paste -sd'|' -)
if [ -n "$enums" ]; then
  # only declared types (`name: Type<...>` before any `=`), not local `val x = listOf<E>()` initializers
  SKIP="$NONPUB" \
  scan "Enums inside collections in the API (KT-90088: Swift crashes casting them at runtime -> known-issues.md)" "^[^=]*: *[^=]*(List|Set|Map|Collection|Array)<([^>]*[<, ])?($enums)[>?, ]" "${KT[@]}"
fi
# all non-test source sets: the rewrite (Phase 1 step 3) changes every platform's DI
PATH_SKIP='^[^:]*/src/[A-Za-z0-9]*Test/' \
  scan "Koin compiler plugin annotations (Phase 1 step 3 rewrite needs the user's permission)" '^[[:space:]]*@(Single|Factory|KoinViewModel|Module|ComponentScan)\b' "${KT[@]}"
scan "Reified inline functions (not exported)" 'inline fun *<[^>]*reified' "${KT[@]}"
scan "protected members (not visible in Swift)" '^\s*protected ' "${KT[@]}"
scan "Kotlin classes extending NSObject / ObjC protocols (not exported)" ': *(platform\.[A-Za-z.]+\.)?NSObject\(\)|Protocol\b.*\{' "${KT[@]}"
# public ArrayList/HashMap/... in signatures export as opaque classes: Swift `as! [T]` always fails
SKIP="$NONPUB" scan "Public ArrayList/HashMap/HashSet property or return types (opaque class in Swift, 'as! [T]' always fails -> declare List/Map/Set)" \
  '(val|var) +[A-Za-z0-9_]+ *: *[^=]*\b(ArrayList|HashMap|HashSet|LinkedHashMap|LinkedHashSet)<|fun [^=]*\) *: *[^=]*\b(ArrayList|HashMap|HashSet|LinkedHashMap|LinkedHashSet)<' "${KT[@]}"
# KT-90497 (as designed): member properties with these names are dropped; Swift silently reads NSObject's
SKIP="$NONPUB" scan "Member properties named like NSObject properties (dropped in Swift, KT-90497 -> rename or @ObjCName(swiftName = \"description_\"))" \
  '(val|var) +(description|debugDescription|hash|hashValue|superclass) *[:=]' "${KT[@]}"
scan "Functions named init / copy (ObjC renamed them; rename for clarity, R4)" 'fun (init|copy)\(' "${KT[@]}"
scan "Callback-style async API (consider suspend/Flow)" '(callback|completion|onResult|onSuccess) *: *\(' "${KT[@]}"

SCAN_ROOTS=("$ROOT"); PATH_SKIP=""

section "Swift: ObjC-export idioms to rewrite"
scan "File facades (XxxKt.)" '\b[A-Z][A-Za-z0-9_]*Kt\.' "${SWIFT[@]}"
scan "Boxed Kotlin primitives / Unit / Nothing / KotlinArray" '\bKotlin(Int|Long|Short|Byte|UInt|ULong|UShort|UByte|Float|Double|Boolean|Char|Number|Unit|Nothing|Array|MutableSet|MutableDictionary|Throwable|Exception|Enum|Pair|Triple)\b' "${SWIFT[@]}"
scan "Unboxing accessors" '\.(intValue|int32Value|int64Value|boolValue|doubleValue|floatValue|stringValue)\b' "${SWIFT[@]}"
scan "Companion via .companion" '\.companion\b' "${SWIFT[@]}"
scan "ObjC 'do' renames (doCopy/doInit/...)" '\bdo(Copy|Init|[A-Z][a-z]+)\(' "${SWIFT[@]}"
scan "Completion handlers (suspend via ObjC)" 'completionHandler' "${SWIFT[@]}"
scan "KMP-NativeCoroutines Swift API" 'asyncFunction\(for:|asyncSequence\(for:|asyncResult\(for:|createPublisher|createFuture|createObservable|createSingle|KMPNativeCoroutines' "${SWIFT[@]}"
scan "SKIE Swift API" 'onEnum\(of:|Observing\(|collect\(flow:|SkieSwift|SkieKotlin|\.toAsyncSequence' "${SWIFT[@]}"
SKIP='outer__:' scan "ObjC-mangled overload labels (param_:) / @ShouldRefineInSwift __members" '\b[a-z][A-Za-z0-9]*_+:|\b__[a-z][A-Za-z0-9]*' "${SWIFT[@]}"
scan "Flow collectors / Kotlinx_coroutines_core" 'Kotlinx_coroutines_core|FlowCollector|\.collect\(collector:' "${SWIFT[@]}"
scan "NS bridging wrappers passed to Kotlin" 'NSMutableArray|NSMutableDictionary|NSMutableSet|NSString\(|as NSString|NSNumber\(|as! NSArray|as NSArray' "${SWIFT[@]}"
scan "Generic Kotlin type args in Swift (e.g. Foo<NSString>)" '<(NSString|NSNumber|AnyObject|NSArray|KotlinInt)[^>]*>' "${SWIFT[@]}"
scan "NSError handling of Kotlin exceptions" 'as NSError|as\? NSError|kotlinException|KotlinException' "${SWIFT[@]}"
scan "Imports" '^(@preconcurrency )?import ' "${SWIFT[@]}"

section "Xcode project"
scan "Gradle build phase tasks" 'embedAndSign[A-Za-z]*ForXcode|embedSwiftExportForXcode|syncFramework|podInstall|gradlew' "${XCODE[@]}"
scan "Framework linking / search paths" 'OTHER_LDFLAGS|FRAMEWORK_SEARCH_PATHS|xcode-frameworks|"-framework"' "*.pbxproj" "*.xcconfig"
scan "Deployment targets (must be >= iOS 18 / macOS 15)" 'IPHONEOS_DEPLOYMENT_TARGET|MACOSX_DEPLOYMENT_TARGET|TVOS_DEPLOYMENT_TARGET|WATCHOS_DEPLOYMENT_TARGET|\.iOS\(|\.macOS\(' "${XCODE[@]}"
scan "User script sandboxing (must be NO)" 'ENABLE_USER_SCRIPT_SANDBOXING' "*.pbxproj" "*.xcconfig"
scan "Swift packages referenced (KMP-NativeCoroutines, SKIE, ...)" 'repositoryURL|XCRemoteSwiftPackageReference|productName' "*.pbxproj"
scan "CocoaPods files" 'pod ' "Podfile"

printf '\nDone. Values for later phases + decisions: <SKILL_DIR>/scripts/preflight.sh <REPO_ROOT>. Generated Swift API (after a Swift Export build): <SKILL_DIR>/scripts/find-generated-swift.sh <EXPORT_DIR> (ios-export with the umbrella, else <SHARED_DIR>)\n'
