#!/usr/bin/env bash
# Static audit for Kotlin/Native build performance in a KMP project.
#
# Read-only: scans Gradle properties, build scripts, shell scripts, and CI
# workflows for configurations known to slow Kotlin/Native builds, and prints
# findings as `[SEVERITY] file:line  message  -> reference`.
#
# Usage: audit-native-build.sh [project-root]   (default: current directory)
#
# Exit code: 0 always (findings are advice, not errors), unless the root is
# not a Gradle project at all.

set -uo pipefail

ROOT="${1:-.}"

if [ ! -e "$ROOT/settings.gradle.kts" ] && [ ! -e "$ROOT/settings.gradle" ] \
   && [ ! -e "$ROOT/build.gradle.kts" ] && [ ! -e "$ROOT/build.gradle" ]; then
    echo "error: $ROOT does not look like a Gradle project root" >&2
    exit 1
fi

FINDINGS=0
EXCLUDES=(--exclude-dir=.git --exclude-dir=build --exclude-dir=.gradle --exclude-dir=.kotlin)

# scan <severity> <message> <reference> <grep -E pattern> <include glob>...
scan() {
    local severity="$1" message="$2" reference="$3" pattern="$4"
    shift 4
    local includes=()
    for glob in "$@"; do includes+=(--include="$glob"); done
    local hits
    hits=$(grep -RInE "${EXCLUDES[@]}" "${includes[@]}" -e "$pattern" "$ROOT" 2>/dev/null \
           | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(#|//)' || true)
    [ -z "$hits" ] && return 0
    while IFS= read -r hit; do
        FINDINGS=$((FINDINGS + 1))
        printf '[%s] %s\n        %s\n        -> %s\n' \
            "$severity" "${hit%%:*}:$(echo "$hit" | cut -d: -f2)" "$message" "$reference"
    done <<< "$hits"
}

# require_property <message> <reference> <key> <value>
# Reports when no gradle.properties sets key=value (commented lines ignored).
require_property() {
    local message="$1" reference="$2" key="$3" value="$4"
    if ! grep -RInE "${EXCLUDES[@]}" --include='gradle.properties' \
            -e "^[[:space:]]*${key}[[:space:]]*=[[:space:]]*${value}[[:space:]]*$" \
            "$ROOT" >/dev/null 2>&1; then
        FINDINGS=$((FINDINGS + 1))
        printf '[%s] %s\n        %s\n        -> %s\n' \
            "MEDIUM" "gradle.properties" "$message" "$reference"
    fi
}

echo "== Kotlin/Native build performance audit: $ROOT =="
echo

## 1. Disabled performance defaults (highest impact, safest to fix)

scan HIGH \
    "Kotlin/Native compiler caches disabled (kotlin.native.cacheKind...=none)" \
    "references/caching-and-gradle.md: remove stale workarounds" \
    '^[[:space:]]*kotlin\.native\.cacheKind(\.[A-Za-z0-9]+)?[[:space:]]*=[[:space:]]*none' \
    'gradle.properties'

scan HIGH \
    "Kotlin/Native compiler daemon disabled" \
    "references/caching-and-gradle.md: remove stale workarounds" \
    '^[[:space:]]*kotlin\.native\.disableCompilerDaemon[[:space:]]*=[[:space:]]*true' \
    'gradle.properties'

scan HIGH \
    "Gradle daemon disabled" \
    "references/caching-and-gradle.md: remove stale workarounds" \
    '^[[:space:]]*org\.gradle\.daemon[[:space:]]*=[[:space:]]*false' \
    'gradle.properties'

scan HIGH \
    "disableNativeCache(...) in build DSL" \
    "references/caching-and-gradle.md: remove stale workarounds" \
    'disableNativeCache[[:space:]]*\(' \
    '*.gradle.kts' '*.gradle'

scan MEDIUM \
    "Configuration on Demand is unsupported by KMP and is not the configuration cache" \
    "references/caching-and-gradle.md: enable Gradle caching" \
    '^[[:space:]]*org\.gradle\.configureondemand[[:space:]]*=[[:space:]]*true' \
    'gradle.properties'

scan MEDIUM \
    "Gradle build cache explicitly disabled" \
    "references/caching-and-gradle.md: enable Gradle caching" \
    '^[[:space:]]*org\.gradle\.caching[[:space:]]*=[[:space:]]*false' \
    'gradle.properties'

require_property \
    "org.gradle.caching=true is not set" \
    "references/caching-and-gradle.md: enable Gradle caching" \
    'org\.gradle\.caching' 'true'

require_property \
    "org.gradle.configuration-cache=true is not set (trial it with the real task first)" \
    "references/caching-and-gradle.md: enable Gradle caching" \
    'org\.gradle\.configuration-cache' 'true'

## 2. Framework exports

scan HIGH \
    "transitiveExport = true disables dead code elimination in many cases" \
    "references/exports-and-generated-code.md: framework exports" \
    'transitiveExport[[:space:]]*=[[:space:]]*true' \
    '*.gradle.kts' '*.gradle'

## 3. Generated code on the native path

scan MEDIUM \
    "kapt in a KMP build; if it shows up before compileKotlinIos*, it is on the hot path" \
    "references/exports-and-generated-code.md: generated code" \
    'kotlin\("kapt"\)|kotlin-kapt|plugins\.kotlin\.kapt|^[[:space:]]*kapt\(' \
    '*.gradle.kts' '*.gradle' '*.toml'

scan INFO \
    "broad ksp(...) dependency; prefer per-target add(\"ksp<Target>\", ...) in KMP" \
    "references/exports-and-generated-code.md: generated code" \
    '^[[:space:]]*ksp\(' \
    '*.gradle.kts' '*.gradle'

## 4. Targets and local build scope

scan INFO \
    "iosX64 target declared; confirm Intel-based simulators are still supported" \
    "references/artifacts-and-targets.md: target matrix" \
    'iosX64[[:space:]]*\(' \
    '*.gradle.kts' '*.gradle'

scan MEDIUM \
    "broad or release Gradle task in a shell script; if this is the local loop, narrow it" \
    "references/artifacts-and-targets.md: task table" \
    'gradlew?[^#]*([[:space:]](clean|build|assemble)([[:space:]]|$)|XCFramework|linkRelease)' \
    '*.sh'

## 5. CI cold starts

WORKFLOW_HITS=$(grep -RIlE "${EXCLUDES[@]}" --include='*.yml' --include='*.yaml' \
    -e 'gradlew|gradle/actions|setup-gradle' "$ROOT/.github" 2>/dev/null || true)
for wf in $WORKFLOW_HITS; do
    if ! grep -qE '\.konan' "$wf"; then
        FINDINGS=$((FINDINGS + 1))
        printf '[%s] %s\n        %s\n        -> %s\n' \
            "MEDIUM" "$wf" \
            "workflow runs Gradle but does not cache ~/.konan (cold Kotlin/Native toolchain every run)" \
            "references/caching-and-gradle.md: keep .konan warm in CI"
    fi
done

## 6. Informational

scan INFO \
    "konan.data.dir relocates the Kotlin/Native cache; confirm the new location is preserved" \
    "references/caching-and-gradle.md: keep .konan warm in CI" \
    '^[[:space:]]*konan\.data\.dir[[:space:]]*=' \
    'gradle.properties'

scan INFO \
    "experimental kotlin.incremental.native is enabled; keep it labeled experimental in reports" \
    "references/experimental.md" \
    '^[[:space:]]*kotlin\.incremental\.native[[:space:]]*=[[:space:]]*true' \
    'gradle.properties'

echo
if [ "$FINDINGS" -eq 0 ]; then
    echo "No static findings. Measure before concluding the build is healthy:"
    echo "run the user's real command twice and check per-task time with"
    echo "kotlin.build.report.output=file or --scan."
else
    echo "$FINDINGS finding(s). Confirm each against the project's policy before fixing;"
    echo "measure before and after with the same command (see SKILL.md, Step 1)."
fi
exit 0
