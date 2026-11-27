#!/usr/bin/env bash
# Phase 0 preflight for a Swift Export migration. Read-only. bash 3.2 / BSD tools.
# Usage: preflight.sh <REPO_ROOT>        (PREFLIGHT_OFFLINE=1 skips the Maven/Plugin Portal lookups, which send
#                                         the project's plugin IDs to public repositories;
#                                         PREFLIGHT_KOTLIN=<version>: the Kotlin version the user named)
#
# Prints KEY=value lines (values that later phases use: <SHARED_MODULE>, <SHARED_DIR>, <BASENAME>, <ROOT_PKG>,
# <APP_TARGETS>, <XCODE_PROJECT>, schemes, <BUNDLE_ID>, ...), then NOTES (informational, no answer needed) and
# "DECISIONS FOR THE USER" (always printed). Values marked "guess" must be confirmed by reading their files.
# Paths may contain spaces: file lists are newline-separated and never word-split.
# Never read stdin: a grep whose file list expands to nothing would otherwise wait forever.
exec </dev/null
set -u

ROOT="$(cd "${1:-.}" && pwd)" || exit 2
HERE="$(cd "$(dirname "$0")" && pwd)"
OFFLINE="${PREFLIGHT_OFFLINE:-0}"
USER_KOTLIN="${PREFLIGHT_KOTLIN:-}"
DECISIONS=""
NOTES=""
decide() { DECISIONS="$DECISIONS$1"$'\n'; }
note() { NOTES="$NOTES$1"$'\n'; }
kv() { printf '%s=%s\n' "$1" "$2"; }
section() { printf '\n## %s\n' "$1"; }
rel() { printf '%s' "${1#"$ROOT"/}"; }
strip_root() { awk -v r="$ROOT/" 'index($0, r) == 1 { $0 = substr($0, length(r) + 1) } { print }'; }
# xeach <newline-separated file list> <command> [args...]: run command with the files appended (none: not run)
xeach() { local list="$1"; shift; [ -n "$list" ] || return 1; printf '%s\n' "$list" | sed '/^$/d' | tr '\n' '\000' | xargs -0 "$@"; }
# xgrep <list> <grep args...>: grep over the list; always prefixes file names with -n/-l like a multi-file grep
xgrep() { local list="$1"; shift; xeach "$list" grep "$@" /dev/null 2>/dev/null; }
# files <find -name args...>: project files, skipping build output and vendored dirs
files() {
  find "$ROOT" \( -name build -o -name .gradle -o -name .kotlin -o -name .git -o -name Pods -o -name DerivedData \
    -o -name .build -o -name node_modules -o -name SwiftPackage -o -name xcuserdata -o -name .idea \) -prune \
    -o -type f \( "$@" \) -print 2>/dev/null | sort
}
join() { paste -sd, - | sed 's/,/, /g'; }
stable() { grep -E '^[0-9]+(\.[0-9]+)*$'; }
vmajor() { printf '%s' "$1" | sed -E 's/[^0-9.].*$//' | cut -d. -f1; }
pname() { case "$1" in ios) echo iOS ;; macos) echo macOS ;; tvos) echo tvOS ;; watchos) echo watchOS ;; visionos) echo visionOS ;; *) echo "$1" ;; esac; }
vlt() { [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n 1)" = "$1" ]; }   # $1 < $2

GRADLE_FILES=$(files -name '*.gradle.kts' -o -name '*.gradle')
CATALOGS=$(files -name '*.versions.toml')
BUILD_FILES=$(printf '%s\n%s\n' "$GRADLE_FILES" "$CATALOGS" | sed '/^$/d')
# Convention-plugin code (buildSrc, build-logic, convention-plugins, gradle/plugins, includeBuild(...) dirs, and
# precompiled script plugins under */src/) is not a module build file; it is searched separately.
INCL=$(cat "$ROOT"/settings.gradle* 2>/dev/null | grep -oE "includeBuild *\(? *[\"'][^\"']+[\"']" \
  | sed -E "s/.*[\"']([^\"']+)[\"'].*/\1/; s|^\./||; s|/$||; s/[.]/\\\\./g" | paste -sd'|' -)
CONV_RE="^(buildSrc|build-logic|convention-plugins|gradle/plugins${INCL:+|$INCL})/"
reroot() { awk -v r="$ROOT/" 'NF { print r $0 }'; }
MOD_GRADLE=$(printf '%s\n' "$GRADLE_FILES" | strip_root | grep -vE "$CONV_RE|/src/" | reroot)
CONV_FILES=$( { printf '%s\n' "$GRADLE_FILES" | strip_root | grep -E "$CONV_RE|/src/"; \
  files -name '*.kt' | strip_root | grep -E "$CONV_RE"; } | sort -u | reroot)

# ---------------------------------------------------------------------------------------------------------
section "TOOLCHAIN"
# catalog_version <key>: value of [versions] key
catalog_version() {
  [ -n "$CATALOGS" ] || return 0
  printf '%s\n' "$CATALOGS" | while IFS= read -r c; do
    [ -n "$c" ] || continue
    awk -v k="$1" '/^\[/{s=$0} s=="[versions]" && $0 ~ "^[ \t]*\"?"k"\"?[ \t]*=" { sub(/^[^=]*=[ \t]*/, ""); gsub(/["\047]/, ""); sub(/[ \t]*#.*$/, ""); print; exit }' "$c"
  done | head -n 1
}
KOTLIN=$(catalog_version kotlin)
KOTLIN_SRC="catalog"
if [ -z "$KOTLIN" ]; then
  KOTLIN=$(xgrep "$GRADLE_FILES" -hoE 'kotlin\("multiplatform"\) version "[^"]+"|id\("org\.jetbrains\.kotlin\.multiplatform"\) version "[^"]+"' \
    | head -n 1 | sed -E 's/.*"([^"]+)"$/\1/')
  KOTLIN_SRC="build script"
fi
kv KOTLIN_VERSION "${KOTLIN:-unknown} ($KOTLIN_SRC)"
GW="$ROOT/gradle/wrapper/gradle-wrapper.properties"
[ -f "$GW" ] && kv GRADLE_VERSION "$(grep distributionUrl "$GW" | sed -E 's/.*gradle-([0-9.]+[^-]*)-(bin|all).*/\1/')"
command -v xcodebuild >/dev/null 2>&1 && kv XCODE_VERSION "$(xcodebuild -version 2>/dev/null | head -n 1 | sed 's/Xcode //')"
if [ -n "$KOTLIN" ]; then
  KVRE=$(printf '%s' "$KOTLIN" | sed 's/\./\\./g')
  LITS=$(xgrep "$BUILD_FILES" -nE "[\"':]${KVRE}[\"']" | grep -vE '\.toml:[0-9]+:[ \t]*kotlin[ \t]*=' \
    | strip_root | cut -d: -f1,2 | join)
  kv KOTLIN_VERSION_LITERALS "${LITS:-none} (hard-coded copies of the Kotlin version; must follow the bump)"
fi

# ---------------------------------------------------------------------------------------------------------
section "KOTLIN MODULE BUILDING THE APPLE FRAMEWORK"
# ObjC framework, CocoaPods, XCFramework, the deprecated swiftExport {} DSL, or export { swift { } }
FW_RE='binaries\.framework|\bframework *\{|cocoapods *\{|XCFramework\(|xcodeIntegration|swiftPackageIntegration|swiftExport *\{|(^|[^A-Za-z.])swift *\{'
FW_FILES=$(xgrep "$MOD_GRADLE" -lE "$FW_RE")
CONV_FW=$(xgrep "$CONV_FILES" -lE "$FW_RE")
[ -n "$CONV_FW" ] && kv CONVENTION_PLUGIN_FRAMEWORK "$(printf '%s\n' "$CONV_FW" | strip_root | join) (framework / Swift Export config lives in convention-plugin code: edit it there; it applies to <SHARED_MODULE>)"
# deprecated swiftExport { } DSL (Kotlin 2.2-2.4): must be migrated to export { swift { } } and deleted
OLD_DSL=$( { xgrep "$MOD_GRADLE" -lE 'swiftExport *\{'; xgrep "$CONV_FILES" -lE 'swiftExport *\{'; } | strip_root | sort -u | join)
[ -n "$OLD_DSL" ] && kv DEPRECATED_SWIFT_EXPORT_DSL "$OLD_DSL (old swiftExport { } block: migrating it to export { swift { } } and deleting it is mandatory, gradle-and-xcode.md §1b)"
# Xcode Run Script tasks (they name the Gradle path)
PROJECTS=$(find "$ROOT" \( -name build -o -name Pods -o -name .build -o -name node_modules -o -name DerivedData -o -name .git \) -prune \
  -o -name '*.xcodeproj' -type d -print 2>/dev/null | sort)
PBX_OUT=""
while IFS= read -r p; do
  [ -n "$p" ] && [ -f "$p/project.pbxproj" ] || continue
  out=$(awk -f "$HERE/lib/pbxproj.awk" "$p/project.pbxproj" 2>/dev/null | awk -v pre="$(rel "$p")" '{ print pre "\t" $0 }')
  PBX_OUT="$PBX_OUT$out"$'\n'
done <<EOF
$PROJECTS
EOF
RUN_TASKS=$(printf '%s' "$PBX_OUT" | awk -F'\t' '$2=="TARGET" && $7!="-" {print $7}' | tr ',' '\n' | sort -u)
# modules named by Run Script tasks; those calling embedSwiftExportForXcode (an umbrella) first
TASK_MODULES=$( { printf '%s\n' "$RUN_TASKS" | grep -E '^:.*:embedSwiftExportForXcode$'; printf '%s\n' "$RUN_TASKS" | grep -E '^:'; } \
  | sed -E 's/:[^:]+$//' | awk 'NF && !s[$0]++')

SHARED_MODULES=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  d=$(dirname "$f"); [ "$d" = "$ROOT" ] && continue
  gp=":$(rel "$d" | tr '/' ':')"
  SHARED_MODULES="$SHARED_MODULES$gp	$(rel "$d")	$(rel "$f")"$'\n'
done <<EOF
$FW_FILES
EOF
SHARED_MODULES=$(printf '%s' "$SHARED_MODULES" | sed '/^$/d')
PICK=""
for m in $TASK_MODULES; do PICK=$(printf '%s\n' "$SHARED_MODULES" | awk -F'\t' -v m="$m" '$1==m' | head -n 1); [ -n "$PICK" ] && break; done
# no build file matched the module the Run Script names (config in a convention plugin or a custom wrapper):
# trust the Run Script, if that module has a build file
if [ -z "$PICK" ]; then
  for m in $TASK_MODULES; do
    d=$(printf '%s' "${m#:}" | tr ':' '/')
    bf=$(ls "$ROOT/$d"/build.gradle.kts "$ROOT/$d"/build.gradle 2>/dev/null | head -n 1)
    if [ -n "$d" ] && [ -n "$bf" ]; then
      PICK="$m	$d	$(rel "$bf")"; SHARED_MODULES=$(printf '%s\n%s\n' "$SHARED_MODULES" "$PICK" | sed '/^$/d')
      note "$m: taken from the Xcode Run Script (its build file has no framework/export block${CONV_FW:+; the convention plugin configures it}): confirm by reading $(rel "$bf")"
      break
    fi
  done
fi
[ -n "$PICK" ] || PICK=$(printf '%s\n' "$SHARED_MODULES" | head -n 1)
NMOD=$(printf '%s\n' "$SHARED_MODULES" | sed '/^$/d' | wc -l | tr -d ' ')
[ "$NMOD" -gt 1 ] && kv FRAMEWORK_MODULES "$(printf '%s\n' "$SHARED_MODULES" | cut -f1 | join) (several; picked the one the Run Script calls)"
SHARED_MODULE=$(printf '%s' "$PICK" | cut -f1)
SHARED_DIR=$(printf '%s' "$PICK" | cut -f2)
SHARED_FILE="$ROOT/$(printf '%s' "$PICK" | cut -f3)"
# already-migrated umbrella (xcodeIntegration + api(project(":x"))): report it, use the module behind it
if [ -n "$SHARED_MODULE" ] && grep -q 'xcodeIntegration' "$SHARED_FILE"; then
  UP=$(grep -hoE 'api\((project\(":[^"]+"\)|projects\.[A-Za-z0-9_.]+)\)' "$SHARED_FILE" | head -n 1 \
    | sed -E 's/api\(project\("([^"]+)"\)\)/\1/; s/api\(projects\.([A-Za-z0-9_.]+)\)/:\1/; s/\./:/g')
  if [ -n "$UP" ]; then
    kv UMBRELLA_MODULE "$SHARED_MODULE (already has xcodeIntegration(): migration in progress or done)"
    SHARED_MODULE="$UP"; SHARED_DIR=$(printf '%s' "${UP#:}" | tr ':' '/'); SHARED_FILE=$(ls "$ROOT/$SHARED_DIR"/build.gradle* 2>/dev/null | head -n 1)
  fi
fi
if [ -n "$SHARED_MODULE" ]; then
  kv SHARED_MODULE "$SHARED_MODULE"
else
  kv SHARED_MODULE "not found — STOP: identify it by hand (the module the Run Script task names${RUN_TASKS:+: $(printf '%s\n' "$RUN_TASKS" | join)}, or the one applying the framework convention plugin)"
  decide "Kotlin module building the Apple framework: not found by preflight (no framework / export block in a module build file, no usable Run Script task). Identify it by reading the build files and convention plugins; ask the user if it stays unclear. Targets are not classified until it is known."
fi
kv SHARED_DIR "${SHARED_DIR:-?}"
grep -qE 'projectDir *=' "$ROOT"/settings.gradle* 2>/dev/null && note "settings.gradle sets projectDir: check that <SHARED_MODULE> matches <SHARED_DIR>"

BASENAME=""; KPLATS=""
if [ -n "$SHARED_MODULE" ]; then
  # old framework baseName (module, else convention plugin); else the deprecated swiftExport { moduleName }
  BASENAME=$( { grep -hE 'baseName *= *"' "$SHARED_FILE"; xgrep "$CONV_FW" -hE 'baseName *= *"'; } | head -n 1 | sed -E 's/.*baseName *= *"([^"]+)".*/\1/')
  [ -z "$BASENAME" ] && grep -qE 'swiftExport *\{|(^|[^A-Za-z.])swift *\{' "$SHARED_FILE" && BASENAME=$(grep -hE 'moduleName *= *"' "$SHARED_FILE" | head -n 1 | sed -E 's/.*moduleName *= *"([^"]+)".*/\1/')
  if [ -n "$BASENAME" ]; then kv BASENAME "$BASENAME"
  else BASENAME=$(basename "$SHARED_DIR"); kv BASENAME "$BASENAME (guess: no literal baseName; default is the project name)"; fi

  # Kotlin targets of the shared module (or its convention plugins)
  TSRC="$SHARED_FILE"
  APPLE_T=$(grep -hoE '\b(ios|macos|tvos|watchos)(X64|Arm64|SimulatorArm64|DeviceArm64|Arm32)\b' "$SHARED_FILE" | sort -u)
  if [ -z "$APPLE_T" ] && [ -n "$CONV_FILES" ]; then
    APPLE_T=$(xgrep "$CONV_FILES" -hoE '\b(ios|macos|tvos|watchos)(X64|Arm64|SimulatorArm64|DeviceArm64|Arm32)\(' | tr -d '(' | sort -u) && TSRC="convention plugins"
  fi
  kv KOTLIN_APPLE_TARGETS "$(printf '%s\n' "$APPLE_T" | sed '/^$/d' | join) (from $(rel "$TSRC"))"
  KPLATS=$(printf '%s\n' "$APPLE_T" | sed -E 's/(X64|Arm64|SimulatorArm64|DeviceArm64|Arm32)$//' | sed '/^$/d' | sort -u | paste -sd, -)
  kv KOTLIN_APPLE_PLATFORMS "${KPLATS:-none}"
  OTHER_T=$(grep -hoE '^[[:space:]]*(jvm|androidTarget|android|js|wasmJs|wasmWasi|mingwX64|linuxX64|linuxArm64|androidNative[A-Za-z0-9]*)[[:space:]]*[({]' "$SHARED_FILE" \
    | sed -E 's/[[:space:]({]//g' | sort -u | join)
  kv OTHER_KOTLIN_TARGETS "${OTHER_T:-none} (never remove or change these)"

  # root package guess: common prefix of packages in source sets that can reach Apple
  PKGS=$(find "$ROOT/$SHARED_DIR/src" -name '*.kt' -type f 2>/dev/null \
    | grep -vE '/src/(android|jvm|desktop|js|wasm|mingw|linux|windows|server)[A-Za-z0-9]*Main/|/src/[A-Za-z0-9]*Test/' \
    | tr '\n' '\000' | xargs -0 grep -h '^package ' /dev/null 2>/dev/null | sed -E 's/^package[[:space:]]+//; s/[[:space:];].*$//')
  ROOT_PKG=$(printf '%s\n' "$PKGS" | sed '/^$/d' | awk -F. 'NR==1{n=NF; for(i=1;i<=NF;i++) p[i]=$i; next}
    { m=(NF<n?NF:n); for(i=1;i<=m;i++) if($i!=p[i]) break; n=i-1 }
    END { s=""; for(i=1;i<=n;i++) s=s (i>1?".":"") p[i]; print s }')
  kv ROOT_PKG "${ROOT_PKG:-?} (guess: common package prefix of commonMain/apple/ios sources)"
  kv ROOT_PKG_TOP "$(printf '%s\n' "$PKGS" | sed '/^$/d' | sort | uniq -c | sort -rn | head -n 4 | awk '{print $2"("$1")"}' | join)"
  # api(...) in every source set of the build file (Kotlin DSL and Groovy); own modules don't count
  API_ALL=$(grep -hoE "\bapi(\(| +)(libs\.[A-Za-z0-9_.]+|project\([^)]*\)|projects\.[A-Za-z0-9_.]+|\"[^\"]+\"|'[^']+'|kotlin\([^)]*\))" "$SHARED_FILE" \
    | sed -E 's/^api(\(| +)//' | sort -u)
  API_LIBS=$(printf '%s\n' "$API_ALL" | grep -vE '^(project\(|projects\.)' | sed '/^$/d' | join)
  if [ -n "$API_LIBS" ]; then kv SHARED_API_DEPS "$API_LIBS (library api deps are exported in full -> use the :ios-export umbrella, EXPORT_MODULE=:ios-export)"
  else kv SHARED_API_DEPS "none in the build file${API_ALL:+ besides own modules ($(printf '%s\n' "$API_ALL" | join))} (plugins can add more: run the API_CONFIGS check, gradle-and-xcode.md §1, before choosing direct export)"; fi
  # api configurations of the source sets that reach Apple: common/native/apple/<platform>/<target>Main + custom ones
  SS=$( { echo commonMain nativeMain appleMain; for p in $(printf '%s' "$KPLATS" | tr ',' ' '); do echo "${p}Main"; done; \
    printf '%s\n' "$APPLE_T" | sed '/^$/d; s/$/Main/'; \
    grep -oE '\b[a-z][A-Za-z0-9]*Main\b' "$SHARED_FILE" | grep -vE '^(android|jvm|js|wasm|mingw|linux|windows|desktop|server|web|androidNative)'; } \
    | tr ' ' '\n' | sed '/^$/d' | awk '!s[$0]++' | sed 's/$/Api/' | join)
  kv API_CONFIGS "$SS"
fi

# ---------------------------------------------------------------------------------------------------------
section "OBJC-EXPORT PLUGINS"
# plugin_hits <regex>: build files / catalogs that mention it
plugin_hits() { xgrep "$BUILD_FILES" -lE "$1" | strip_root | join; }
SKIE=$(plugin_hits 'co\.touchlab\.skie|plugins\.skie\b')
KMPNC=$(plugin_hits 'com\.rickclephas\.kmp\.nativecoroutines|nativecoroutines')
# CocoaPods only counts if it builds the Kotlin framework: the Gradle plugin, or a Podfile that names the Kotlin pod
PODS=$(plugin_hits 'native\.cocoapods|cocoapods *\{')
PODFILES=$(files -name Podfile)
KPODS=""; OPODS=""
while IFS= read -r pf; do
  [ -n "$pf" ] || continue
  if { [ -n "$BASENAME" ] && grep -qE "pod +['\"]$BASENAME['\"]" "$pf"; } || { [ -n "$SHARED_DIR" ] && grep -qE ":path *=> *['\"][^'\"]*$SHARED_DIR" "$pf"; }; then
    KPODS="${KPODS:+$KPODS, }$(rel "$pf")"
  else OPODS="${OPODS:+$OPODS, }$(rel "$pf")"; fi
done <<EOF
$PODFILES
EOF
[ -n "$KPODS" ] && PODS="${PODS:+$PODS, }$KPODS"
[ -n "$OPODS" ] && note "Podfile present for other pods ($OPODS), not for the Kotlin framework: unaffected by the migration."
SWPKG=$(plugin_hits 'multiplatform-swiftpackage|multiplatformSwiftPackage')
KMMB=$(plugin_hits 'kmmbridge|KMMBridge')
XCF=$(xgrep "$GRADLE_FILES" -lE 'XCFramework\(' | strip_root | join)
kv SKIE "${SKIE:-no}"
# skie { ... } block contents (features in use decide which Swift helpers Phase 5 must replace)
[ -n "$SKIE" ] && kv SKIE_CONFIG "$(xeach "$GRADLE_FILES" awk '/(^|[^A-Za-z])skie *\{/ && !d { d=1; c=0 } d { l=$0; o=gsub(/\{/, "{", l); x=gsub(/\}/, "}", l); c+=o-x; t=$0; gsub(/^[ \t]+|[ \t]+$/, "", t); if (t !~ /^(skie|features) *\{$|^\}$/ && t != "") print t; if (c<=0) d=0 }' 2>/dev/null | join)"
kv KMP_NATIVECOROUTINES "${KMPNC:-no}"
kv COCOAPODS "${PODS:-no}"
kv PACKAGING_MULTIPLATFORM_SWIFTPACKAGE "${SWPKG:-no}"
kv PACKAGING_KMMBRIDGE "${KMMB:-no}"
kv PACKAGING_XCFRAMEWORK_TASK "${XCF:-no}"
# names of the Swift packages / XCFrameworks those plugins produce
PKFILES=$(xgrep "$GRADLE_FILES" -lE 'multiplatformSwiftPackage|kmmbridge')
PRODUCED=$( { xgrep "$PKFILES" -hoE 'packageName\("[^"]+"\)|packageName *= *"[^"]+"'; \
  xgrep "$GRADLE_FILES" -hoE 'XCFramework\("[^"]+"\)'; } | sed -E 's/.*"([^"]+)".*/\1/' | sort -u)
[ -n "$PRODUCED" ] && kv PACKAGING_PRODUCES "$(printf '%s\n' "$PRODUCED" | join)"
PACKAGERS=$(printf '%s\n' "${SWPKG:+multiplatform-swiftpackage}" "${KMMB:+KMMBridge}" "${XCF:+XCFramework task}" | sed '/^$/d' | join)
PACK_LOCS=$(printf '%s\n' "$SWPKG" "$KMMB" "$XCF" | tr ',' '\n' | sed 's/^ *//; /^$/d' | sort -u | join)

# ---------------------------------------------------------------------------------------------------------
section "XCODE"
i=0
while IFS= read -r p; do [ -n "$p" ] || continue; i=$((i + 1)); kv "XCODE_PROJECT_$i" "$(rel "$p")"; done <<EOF
$PROJECTS
EOF
WS=$(find "$ROOT" \( -name build -o -name Pods -o -name .build -o -name '*.xcodeproj' -o -name .git \) -prune -o -name '*.xcworkspace' -type d -print 2>/dev/null)
while IFS= read -r w; do [ -n "$w" ] && kv XCODE_WORKSPACE "$(rel "$w") (build with -workspace)"; done <<EOF
$WS
EOF
SCHEME_FILES=$(files -name '*.xcscheme')
# schemes_for <target>: shared schemes whose build action builds the target
schemes_for() {
  printf '%s\n' "$SCHEME_FILES" | while IFS= read -r sf; do
    [ -n "$sf" ] || continue
    grep -A8 '<BuildActionEntry' "$sf" 2>/dev/null | grep -qF "BlueprintName = \"$1\"" && basename "$sf" .xcscheme
  done | sort -u | join
}
kv RUN_SCRIPT_TASKS "$(printf '%s\n' "$RUN_TASKS" | sed '/^$/d' | join)"
APP_TARGETS=""; OUT_TARGETS=""; UNK_TARGETS=""; APP_INFO=""; n=0
while IFS=$'\t' read -r proj kind name ptype plats dts tasks before fws fsp sb xc prods bid; do
  [ "$kind" = "TARGET" ] || continue
  n=$((n + 1))
  links=no
  case "$tasks" in *ForXcode*|*syncFramework*) links=yes ;; esac
  case ",$fws," in *",$BASENAME,"*) links=yes ;; esac
  case "$fsp" in *xcode-frameworks*) links=yes ;; esac
  for pr in $PRODUCED $BASENAME; do case ",$prods," in *",$pr,"*) links=yes ;; esac; done
  built=no
  for pl in $(printf '%s' "$plats" | tr ',' ' '); do case ",${KPLATS:-}," in *",$pl,"*) built=yes ;; esac; done
  # without a known module / Kotlin Apple targets nothing can be ruled out of scope
  [ -z "$SHARED_MODULE" ] || [ -z "$KPLATS" ] && built=unknown
  ty=${ptype#com.apple.product-type.}
  kv "TARGET_$n" "$name | project=$proj | type=$ty | platform=$plats | deployment=$dts | links_kotlin=$links | platform_built_by_kotlin=$built | run_script=$tasks | before_sources=$before | ldflags=$fws | sandboxing=$sb | xcconfig=$xc | spm_products=$prods | bundle_id=$bid"
  if [ "$links" = yes ] && [ "$built" = unknown ] && [ -z "$SHARED_MODULE" ]; then
    UNK_TARGETS="${UNK_TARGETS:+$UNK_TARGETS,}$name"
  elif [ "$links" = yes ] && [ "$built" != no ]; then
    APP_TARGETS="${APP_TARGETS:+$APP_TARGETS,}$name"
    [ "$built" = unknown ] && note "$name: Kotlin Apple targets of $SHARED_MODULE not found (custom target helper?): check that Kotlin builds $plats"
    sch=$(schemes_for "$name")
    bnote=""; case "$bid" in *'$('*) bnote=" (has build-setting references: xcodebuild -showBuildSettings -project <XCODE_PROJECT> -target $name | grep PRODUCT_BUNDLE_IDENTIFIER)" ;; esac
    APP_INFO="$APP_INFO$name | type=$ty | xcode_project=$proj | schemes=${sch:-none shared (Xcode autocreates one named like the target; check: xcodebuild -list -project $proj)} | bundle_id=$bid$bnote"$'\n'
    for d in $(printf '%s' "$dts" | tr ',' ' '); do
      # d = ios=18.0 or ios=Debug:18.0;Release:17.0 -> the lowest configured value decides
      pl=${d%%=*}; min=18
      [ "$pl" = macos ] && min=15; [ "$pl" = watchos ] && min=11
      v=$(printf '%s\n' "${d#*=}" | tr ';' '\n' | sed 's/^[^:]*://' | grep -E '^[0-9]' | sort -V | head -n 1)
      maj=$(vmajor "$v")
      cfgs=""; case "${d#*=}" in *:*) cfgs=" (per configuration: ${d#*=})" ;; esac
      [ -n "$maj" ] && [ "$maj" -lt "$min" ] && decide "Deployment target: bump $name ($(pname "$pl")) from $v$cfgs to $min.0 in every configuration — Swift Export requires it; the app stops supporting older $(pname "$pl") versions."
      [ -z "$maj" ] && note "$name: $pl deployment target not found in the project (xcconfig?) — check it is >= $min.0"
      case "${d#*=}" in *:-*) [ -n "$maj" ] && note "$name: $pl deployment target is unset in some configurations (${d#*=}): set it in every configuration" ;; esac
    done
    [ "$xc" != "-" ] && note "$name uses xcconfig $xc — build settings may live there"
  elif [ "$links" = yes ]; then
    OUT_TARGETS="${OUT_TARGETS:+$OUT_TARGETS,}$name"
    note "$name ($plats) links the Kotlin framework but $SHARED_MODULE has no $plats target, so it was not building from this module: leave it untouched and mention it in the report."
  fi
done <<EOF
$(printf '%s' "$PBX_OUT" | sed '/^$/d')
EOF
if [ -n "$SHARED_MODULE" ]; then kv APP_TARGETS "${APP_TARGETS:-none}"
else kv APP_TARGETS "unknown (SHARED_MODULE not found; targets linking Kotlin: ${UNK_TARGETS:-none})"; fi
# <XCODE_PROJECT>, <SCHEME> candidates and <BUNDLE_ID> per app target (Debug value if configurations differ)
i=0
while IFS= read -r a; do [ -n "$a" ] || continue; i=$((i + 1)); kv "APP_TARGET_$i" "$a"; done <<EOF
$APP_INFO
EOF
if [ -n "$SHARED_MODULE" ]; then kv OUT_OF_SCOPE_TARGETS "${OUT_TARGETS:-none} (link the framework, but Kotlin does not build their platform)"
else kv OUT_OF_SCOPE_TARGETS "not computed (SHARED_MODULE not found)"; fi
PKGREFS=$(printf '%s' "$PBX_OUT" | awk -F'\t' '$2=="PACKAGE"{print $3":"$4}' | sort -u | join)
kv XCODE_SWIFT_PACKAGES "${PKGREFS:-none}"
if [ -n "$PODS" ]; then INTEG="cocoapods"; elif [ -n "$PACKAGERS" ] && [ -z "$RUN_TASKS" ]; then INTEG="xcframework/spm"
elif [ -n "$RUN_TASKS" ]; then INTEG="direct (Run Script)"; else INTEG="unknown"; fi
kv XCODE_INTEGRATION "$INTEG"

# ---------------------------------------------------------------------------------------------------------
section "SWIFT PACKAGES / CLI CONSUMERS IN THE REPO"
i=0; CONSUMERS=""
while IFS= read -r pkg; do
  [ -n "$pkg" ] || continue
  i=$((i + 1)); d=$(dirname "$pkg")
  nm=$(grep -m1 -oE 'name: *"[^"]+"' "$pkg" | sed -E 's/.*"([^"]+)"/\1/')
  plat=$(tr -d '\n' < "$pkg" | grep -oE 'platforms: *\[[^]]*\]' | sed -E 's/platforms: *//; s/[[:space:]]+//g')
  deps=$(grep -oE '\.package\([^)]*\)' "$pkg" | grep -oE '(url|path): *"[^"]+"' | sed -E 's/: *"/:/; s/"$//' | join)
  prods=$(grep -oE '\.product\( *name: *"[^"]+" *, *package: *"[^"]+"' "$pkg" | sed -E 's/.*name: *"([^"]+)" *, *package: *"([^"]+)"/\1(\2)/' | join)
  bins=$(grep -oE '\.binaryTarget\([^)]*\)' "$pkg" | grep -oE '(url|path): *"[^"]+"' | sed -E 's/: *"/:/; s/"$//' | join)
  kv "SWIFT_PACKAGE_$i" "$(rel "$pkg") | name=$nm | platforms=${plat:-?} | deps=${deps:-none} | products=${prods:-none}${bins:+ | binaryTargets=$bins}"
  uses=""
  for pr in $PRODUCED; do grep -qE "\"$pr\"" "$pkg" && uses="${uses:+$uses, }$pr (produced by ${PACKAGERS:-a packaging task} in $SHARED_MODULE)"; done
  [ -n "$SHARED_DIR" ] && grep -qE "path: *\"[^\"]*$SHARED_DIR" "$pkg" && uses="${uses:+$uses, }a path into $SHARED_DIR"
  [ -n "$BASENAME" ] && grep -qE "\"$BASENAME(\.xcframework)?\"" "$pkg" && uses="${uses:+$uses, }$BASENAME"
  grep -qiE 'KMP-NativeCoroutines|KMPNativeCoroutines' "$pkg" && uses="${uses:+$uses, }KMP-NativeCoroutines Swift package"
  grep -qiE 'skie' "$pkg" && uses="${uses:+$uses, }SKIE"
  if [ -n "$uses" ]; then
    kv "SWIFT_PACKAGE_${i}_USES_KOTLIN" "$uses"
    if [ -n "$PACKAGERS" ] && printf '%s' "$uses" | grep -q 'produced by'; then
      CONSUMERS="${CONSUMERS:+$CONSUMERS; }$(rel "$d") (uses $uses)"
    else
      note "$(rel "$d") uses $uses — check whether it is built from this repo or from a prebuilt/remote copy."
    fi
  fi
done <<EOF
$(files -name Package.swift)
EOF
[ $i -eq 0 ] && kv SWIFT_PACKAGES none
# Packaging/publishing plugins usually feed consumers outside the repo: always the user's decision
[ -n "$PACKAGERS" ] && decide "Packaging/publishing: $PACKAGERS ($PACK_LOCS${PRODUCED:+, produces $(printf '%s\n' "$PRODUCED" | join)}) — it usually publishes to consumers outside this repo (e.g. a remote Swift package repo).${CONSUMERS:+ In-repo consumers: $CONSUMERS.} Options: keep it (keep binaries.framework next to export { } for it), replace it with swiftPackageIntegration() output, or remove it and report its consumers as broken/out of scope. Never remove or replace it without the user's approval."

# ---------------------------------------------------------------------------------------------------------
section "PLUGIN VERSIONS (current vs latest published)"
# id<TAB>version from catalogs ([plugins] with version / version.ref) and inline `id("x") version "y"`
PLUGINS=$(
  printf '%s\n' "$CATALOGS" | while IFS= read -r c; do
    [ -n "$c" ] || continue
    awk '
      /^\[/ { s=$0; next }
      s=="[versions]" && /=/ { k=$0; sub(/[ \t]*=.*/, "", k); gsub(/[ \t"]/, "", k); v=$0; sub(/^[^=]*=[ \t]*/, "", v); gsub(/["\047]/, "", v); sub(/[ \t]*#.*$/, "", v); ver[k]=v }
      s=="[plugins]" && /=/ {
        line=$0; id=""; v=""
        if (match(line, /id *= *"[^"]+"/)) { id=substr(line, RSTART, RLENGTH); sub(/^id *= *"/, "", id); sub(/"$/, "", id) }
        if (match(line, /version\.ref *= *"[^"]+"/)) { r=substr(line, RSTART, RLENGTH); sub(/^version\.ref *= *"/, "", r); sub(/"$/, "", r); v=ver[r] }
        else if (match(line, /version *= *"[^"]+"/)) { v=substr(line, RSTART, RLENGTH); sub(/^version *= *"/, "", v); sub(/"$/, "", v) }
        if (id == "" && match(line, /= *"[^":]+:[^"]+"/)) { x=substr(line, RSTART, RLENGTH); sub(/^= *"/, "", x); sub(/"$/, "", x); split(x, a, ":"); id=a[1]; v=a[2] }
        if (id != "") print id "\t" (v == "" ? "-" : v)
      }' "$c"
  done
  xgrep "$GRADLE_FILES" -hoE 'id\("[^"]+"\) version "[^"]+"' | sed -E 's/id\("([^"]+)"\) version "([^"]+)"/\1	\2/'
  xgrep "$GRADLE_FILES" -hoE 'kotlin\("[^"]+"\) version "[^"]+"' | sed -E 's/kotlin\("([^"]+)"\) version "([^"]+)"/org.jetbrains.kotlin.\1	\2/'
)
PLUGINS=$(printf '%s\n' "$PLUGINS" | sed '/^$/d' | sort -u)
# the Kotlin version list is always needed for KOTLIN_TARGET_VERSION, even when the plugin is applied without a version
printf '%s\n' "$PLUGINS" | grep -q '^org\.jetbrains\.kotlin\.multiplatform	' \
  || PLUGINS=$(printf '%s\norg.jetbrains.kotlin.multiplatform\t%s\n' "$PLUGINS" "${KOTLIN:--}" | sed '/^$/d')
# public plugin IDs the migration itself needs (the only ones looked up by hand when offline)
PUBLIC_RE='^(org\.jetbrains\.kotlin\.multiplatform|com\.google\.devtools\.ksp|com\.rickclephas\.kmp\.nativecoroutines|io\.insert-koin\.compiler\.plugin)$'
if [ "$OFFLINE" != "1" ] && ! curl -fsS -o /dev/null --connect-timeout 4 --max-time 6 https://repo1.maven.org/maven2/ 2>/dev/null; then OFFLINE=1; kv NETWORK "offline — latest versions not checked"; fi
BEHIND=""; KMPNC_VERS=""; KS=""; KP=""; KT=""
KOTLIN_VERS=""
while IFS=$'\t' read -r id cur; do
  [ -n "$id" ] || continue
  if [ "$OFFLINE" = "1" ]; then kv PLUGIN "$id current=$cur latest=not-checked"; continue; fi
  # no version: usually an in-house convention plugin; don't send its ID to public repositories
  if [ "$cur" = "-" ]; then case "$id" in org.jetbrains.*|com.android.*|com.google.*) ;; *) kv PLUGIN "$id current=- latest=not-checked (no version: in-house/convention plugin?)"; continue ;; esac; fi
  ip=$(printf '%s' "$id" | tr '.' '/'); meta=""; src=""
  for base in https://plugins.gradle.org/m2 https://repo1.maven.org/maven2 https://dl.google.com/dl/android/maven2; do
    meta=$(curl -fsSL --connect-timeout 4 --max-time 8 "$base/$ip/$id.gradle.plugin/maven-metadata.xml" 2>/dev/null) && [ -n "$meta" ] && { src=$base; break; }
  done
  if [ -z "$meta" ]; then kv PLUGIN "$id current=$cur latest=not-found"; continue; fi
  vers=$(printf '%s' "$meta" | grep -oE '<version>[^<]+</version>' | sed -E 's/<\/?version>//g')
  lstable=$(printf '%s\n' "$vers" | stable | sort -V | tail -n 1)
  lany=$(printf '%s' "$meta" | grep -oE '<latest>[^<]+</latest>' | sed -E 's/<\/?latest>//g')
  [ -n "$lany" ] || lany=$(printf '%s\n' "$vers" | tail -n 1)
  kv PLUGIN "$id current=$cur latest_stable=${lstable:-none} latest=$lany (${src#https://})"
  [ "$id" = "org.jetbrains.kotlin.multiplatform" ] && KOTLIN_VERS=$vers
  [ "$id" = "com.rickclephas.kmp.nativecoroutines" ] && KMPNC_VERS=$vers
  # bumped by the migration anyway: Kotlin-versioned plugins, KSP and KMP-NC (Phase 1); SKIE is removed
  case "$id" in org.jetbrains.kotlin.*|co.touchlab.skie|com.rickclephas.kmp.nativecoroutines|com.google.devtools.ksp) continue ;; esac
  [ "$cur" = "$KOTLIN" ] && continue
  if [ "$cur" != "-" ] && [ -n "$lstable" ] && vlt "$cur" "$lstable"; then BEHIND="${BEHIND:+$BEHIND, }$id $cur -> $lstable"; fi
done <<EOF
$PLUGINS
EOF
if [ "$OFFLINE" = "1" ]; then
  [ -n "$USER_KOTLIN" ] || kv KOTLIN_TARGET_VERSION "not-checked (offline)"
  PUB=$(printf '%s\n' "$PLUGINS" | cut -f1 | grep -E "$PUBLIC_RE" | join)
  kv TODO_OFFLINE "versions not checked. Before Phase 1 read maven-metadata.xml (https://plugins.gradle.org/m2/<id with . as />/<id>.gradle.plugin/maven-metadata.xml, or the project's mirror) for these public IDs only: ${PUB:-org.jetbrains.kotlin.multiplatform}. Pick Kotlin and KMPNC_FOR_TARGET by the SKILL.md rules. Don't look up the other PLUGIN lines (they may be in-house)."
  [ -n "$USER_KOTLIN" ] || decide "Kotlin version: not checked (offline). Confirm the Kotlin version with the user unless they named one (newest stable 2.5.x, else the newest 2.5.0 pre-release — migrating onto a pre-release is the user's call)."
fi
if [ -n "$USER_KOTLIN" ]; then
  KT=$USER_KOTLIN; kv KOTLIN_TARGET_VERSION "$KT (named by the user: PREFLIGHT_KOTLIN)"
  case "$KT" in 2.5.*) ;; *) note "PREFLIGHT_KOTLIN=$KT is not a 2.5.x version: the export { swift { } } DSL needs Kotlin 2.5.0 or a 2.5.0 pre-release." ;; esac
elif [ -n "$KOTLIN_VERS" ]; then
  # newest stable 2.5.x, else the newest 2.5.0 pre-release (never -dev / -SNAPSHOT builds); newer lines only as a NOTE
  KV=$(printf '%s\n' "$KOTLIN_VERS" | grep -vE 'dev|SNAPSHOT|snapshot')
  KS=$(printf '%s\n' "$KV" | grep -E '^2\.5\.' | stable | sort -V | tail -n 1)
  if [ -n "$KS" ]; then KT=$KS; kv KOTLIN_TARGET_VERSION "$KS (newest stable 2.5.x; use the user's version if they named one)"
  else
    KP=$(printf '%s\n' "$KV" | grep -E '^2\.5\.0-' | sort -V | tail -n 1)
    if [ -n "$KP" ]; then
      KT=$KP
      kv KOTLIN_TARGET_VERSION "$KP (no stable 2.5.x yet; newest 2.5.0 pre-release)"
      decide "Kotlin: no stable 2.5.x is published yet; the newest is the pre-release $KP. Migrating onto a pre-release is the user's call. Answered if the user named a Kotlin version (use theirs)."
    else decide "Kotlin: no 2.5.x release or pre-release is published yet, so Swift Export's export { swift { } } DSL is unavailable. Stop or wait."; fi
  fi
  NEWER=$(printf '%s\n' "$KV" | grep -E '^2\.([6-9]|[1-9][0-9])\.|^[3-9]\.' | stable | sort -V | tail -n 1)
  [ -n "$NEWER" ] && note "Kotlin $NEWER (a newer line than 2.5) is published; this skill targets 2.5.x — use a newer line only if the user asks (check its Swift Export changes first)."
fi
if [ -n "$KMPNC" ] && [ -n "$KMPNC_VERS" ] && [ -n "$KT" ]; then
  # KMP-NC: plain releases (1.0.7) are built for a stable Kotlin; pre-release builds carry it (1.0.7-kotlin-2.5.0-RC)
  KMPNC_T=""; KWHY=""
  case "$KT" in
    *-*)
      re=$(printf '%s' "$KT" | sed 's/[.]/\\./g')
      KMPNC_T=$(printf '%s\n' "$KMPNC_VERS" | grep -E -- "-kotlin-${re}\$" | sort -V | tail -n 1)
      if [ -z "$KMPNC_T" ]; then
        # 2.5.0-RC2 has no own build: the closest is the same pre-release kind (-kotlin-2.5.0-RC*)
        re2=$(printf '%s' "$KT" | sed -E 's/[0-9]+$//; s/[.]/\\./g')
        KMPNC_T=$(printf '%s\n' "$KMPNC_VERS" | grep -E -- "-kotlin-${re2}[0-9]*\$" | sort -V | tail -n 1)
        [ -n "$KMPNC_T" ] && KWHY="; no build for $KT itself, this is the closest"
      fi
      if [ -n "$KMPNC_T" ]; then kv KMPNC_FOR_TARGET "$KMPNC_T (built for Kotlin ${KMPNC_T#*-kotlin-}$KWHY; use it with nativeCoroutines { swiftExport = true }; Swift package: the plain version ${KMPNC_T%%-kotlin-*})"
      else
        kv KMPNC_FOR_TARGET "none built for Kotlin $KT"
        decide "KMP-NativeCoroutines: no release is built for Kotlin $KT (checked the -kotlin-<version> builds). Options: wait for a release, use a Kotlin version it has a build for, or drop KMP-NC (its annotations, plugin, KSP and Swift packages go; Swift call sites are rewritten, R25 cleanup). Removing it needs the user's approval."
      fi ;;
    *)
      KMPNC_T=$(printf '%s\n' "$KMPNC_VERS" | stable | sort -V | tail -n 1)
      if [ -n "$KMPNC_T" ]; then kv KMPNC_FOR_TARGET "$KMPNC_T (newest plain release; confirm in its release notes, github.com/rickclephas/KMP-NativeCoroutines/releases, that it is built for Kotlin $KT — if no release is, that is a Phase 0 decision: wait, other Kotlin, or drop KMP-NC; use it with nativeCoroutines { swiftExport = true }; Swift package: the same version)"
      else
        kv KMPNC_FOR_TARGET "none (no plain release published)"
        decide "KMP-NativeCoroutines: no plain release for Kotlin $KT. Options: wait for a release, use a Kotlin version it has a build for, or drop KMP-NC (R25 cleanup). Removing it needs the user's approval."
      fi ;;
  esac
fi
[ -n "$BEHIND" ] && note "Plugins behind their latest stable release (informational, no answer needed; default: leave them as they are — Phase 1 upgrades only plugins that break on the new Kotlin; upgrade others only if the user asks): $BEHIND."

# ---------------------------------------------------------------------------------------------------------
[ -n "$PODS" ] && decide "CocoaPods ($PODS) builds the Kotlin framework: Swift Export does not support it. First migrate it with the kotlin-tooling-cocoapods-spm-migration skill (CocoaPods -> swiftPMDependencies + direct integration) as a separate, verified step, then run this skill."
[ -n "$SKIE" ] && note "SKIE will be removed (Swift Export replaces it); no permission needed."
[ -n "$KMPNC" ] && note "KMP-NativeCoroutines stays, switched to its Swift Export compatibility mode (KMPNC_FOR_TARGET); removed only with the user's approval (no release for the target Kotlin, a Phase 0 decision) or when the user asks to drop it (then the KMP-NC cleanup is part of Phase 5)."

section "NOTES (informational)"
printf '%s' "${NOTES:-none}"$'\n'
section "DECISIONS FOR THE USER"
if [ -n "$DECISIONS" ]; then printf '%s' "$DECISIONS" | awk '{print "DECISION_" NR "=" $0}'
else echo "DECISIONS=none"; fi
echo
echo "Next (SKILL.md Phase 0): scan, toolchain probe (bump Kotlin, compile JVM + iosSimulatorArm64), then ask the user every DECISION at once."
