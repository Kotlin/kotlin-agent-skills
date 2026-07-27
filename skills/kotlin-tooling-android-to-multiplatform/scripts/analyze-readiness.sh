#!/bin/sh
#
# analyze-readiness.sh - Analyze an Android project for KMP migration readiness
#
# Usage: ./analyze-readiness.sh [PROJECT_ROOT]
#        Defaults to current directory if PROJECT_ROOT is not specified.

set -e

PROJECT_ROOT="${1:-.}"

# Resolve to absolute path
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"

echo "========================================"
echo " Android → KMP Migration Readiness Report"
echo "========================================"
echo ""
echo "Project root: $PROJECT_ROOT"
echo ""

# --- Language Check ---
echo "----------------------------------------"
echo " Language: Java vs Kotlin"
echo "----------------------------------------"
JAVA_COUNT=0
KOTLIN_COUNT=0

JAVA_FILES=$(find "$PROJECT_ROOT" -name "*.java" -not -path "*/build/*" -not -path "*/.gradle/*" 2>/dev/null || true)
KOTLIN_FILES=$(find "$PROJECT_ROOT" -name "*.kt" -not -path "*/build/*" -not -path "*/.gradle/*" 2>/dev/null || true)

if [ -n "$JAVA_FILES" ]; then
    JAVA_COUNT=$(echo "$JAVA_FILES" | wc -l | tr -d ' ')
fi
if [ -n "$KOTLIN_FILES" ]; then
    KOTLIN_COUNT=$(echo "$KOTLIN_FILES" | wc -l | tr -d ' ')
fi

echo "  Kotlin files: $KOTLIN_COUNT"
echo "  Java files:   $JAVA_COUNT"

if [ "$JAVA_COUNT" -eq 0 ]; then
    echo "  ✓ No Java files — ready for KMP"
elif [ "$JAVA_COUNT" -le 5 ]; then
    echo "  ⚠ Few Java files — convert to Kotlin before migrating"
else
    echo "  ✗ Significant Java code — convert to Kotlin first"
fi
echo ""

# --- Java API Usage in Kotlin ---
echo "----------------------------------------"
echo " Java API Usage in Kotlin Files"
echo "----------------------------------------"

check_java_api() {
    PATTERN="$1"
    LABEL="$2"
    MATCHES=$(grep -rl "$PATTERN" "$PROJECT_ROOT" --include="*.kt" 2>/dev/null | grep -v '/build/' | grep -v '/.gradle/' || true)
    if [ -n "$MATCHES" ]; then
        COUNT=$(echo "$MATCHES" | wc -l | tr -d ' ')
        echo "  ⚠ $LABEL: found in $COUNT file(s)"
    fi
}

check_java_api "java\.time\." "java.time usage"
check_java_api "java\.util\.UUID" "java.util.UUID"
check_java_api "java\.net\." "java.net usage"
check_java_api "java\.io\.File" "java.io.File"
check_java_api "System\.currentTimeMillis" "System.currentTimeMillis()"
check_java_api "Objects\.hash" "Objects.hash()"
check_java_api "android\.util\.Log" "android.util.Log"

echo ""

# --- UI Framework ---
echo "----------------------------------------"
echo " UI Framework"
echo "----------------------------------------"

COMPOSE_USAGE=$(grep -rl "@Composable" "$PROJECT_ROOT" --include="*.kt" 2>/dev/null | grep -v '/build/' | grep -v '/.gradle/' || true)
VIEW_USAGE=$(grep -rl "android\.widget\.\|setContentView\|findViewById\|ViewBinding\|DataBindingUtil" "$PROJECT_ROOT" --include="*.kt" --include="*.java" 2>/dev/null | grep -v '/build/' | grep -v '/.gradle/' || true)
XML_LAYOUTS=$(find "$PROJECT_ROOT" -path "*/res/layout/*.xml" -not -path "*/build/*" 2>/dev/null || true)

COMPOSE_COUNT=0
VIEW_COUNT=0
LAYOUT_COUNT=0

if [ -n "$COMPOSE_USAGE" ]; then
    COMPOSE_COUNT=$(echo "$COMPOSE_USAGE" | wc -l | tr -d ' ')
fi
if [ -n "$VIEW_USAGE" ]; then
    VIEW_COUNT=$(echo "$VIEW_USAGE" | wc -l | tr -d ' ')
fi
if [ -n "$XML_LAYOUTS" ]; then
    LAYOUT_COUNT=$(echo "$XML_LAYOUTS" | wc -l | tr -d ' ')
fi

echo "  Compose files: $COMPOSE_COUNT"
echo "  View/binding files: $VIEW_COUNT"
echo "  XML layout files: $LAYOUT_COUNT"

if [ "$COMPOSE_COUNT" -gt 0 ] && [ "$VIEW_COUNT" -eq 0 ] && [ "$LAYOUT_COUNT" -eq 0 ]; then
    echo "  ✓ Pure Compose — ready for Compose Multiplatform"
elif [ "$COMPOSE_COUNT" -gt 0 ] && [ "$VIEW_COUNT" -gt 0 ]; then
    echo "  ⚠ Mixed Compose + Views — Views must stay Android-only or be rewritten"
elif [ "$VIEW_COUNT" -gt 0 ] || [ "$LAYOUT_COUNT" -gt 0 ]; then
    echo "  ✗ Uses Android Views — migrate to Compose before sharing UI"
else
    echo "  No UI code detected (library project?)"
fi
echo ""

# --- Dependency Analysis ---
echo "----------------------------------------"
echo " Dependencies (Android-only detection)"
echo "----------------------------------------"

check_dependency() {
    PATTERN="$1"
    LABEL="$2"
    MATCHES=$(grep -rl "$PATTERN" "$PROJECT_ROOT" --include="*.kts" --include="*.gradle" --include="*.toml" 2>/dev/null | grep -v '/build/' | grep -v '/.gradle/' || true)
    if [ -n "$MATCHES" ]; then
        echo "  ⚠ $LABEL"
    fi
}

echo "  Checking for Android-only dependencies..."
check_dependency "dagger\|hilt" "Dagger/Hilt — replace with Koin or Metro for KMP"
check_dependency "retrofit" "Retrofit — replace with Ktor Client for KMP"
check_dependency "rxjava\|rxkotlin\|rxandroid" "RxJava — replace with coroutines/Flow"
check_dependency "com.google.code.gson" "Gson — replace with kotlinx-serialization"
check_dependency "glide" "Glide — replace with Coil 3 for KMP"
check_dependency "junit" "JUnit — replace with kotlin-test for shared modules"
check_dependency "espresso" "Espresso — Android-only; stays in androidDeviceTest"
check_dependency "robolectric" "Robolectric — Android-only; stays in androidUnitTest"

echo ""

echo "  Checking for KMP-ready dependencies..."
TOML_FILE="$PROJECT_ROOT/gradle/libs.versions.toml"

check_kmp_dep() {
    PATTERN="$1"
    LABEL="$2"
    if [ -f "$TOML_FILE" ] && grep -q "$PATTERN" "$TOML_FILE" 2>/dev/null; then
        echo "  ✓ $LABEL"
    elif grep -rl "$PATTERN" "$PROJECT_ROOT" --include="*.kts" --include="*.gradle" 2>/dev/null | grep -v '/build/' | grep -v '/.gradle/' | head -1 > /dev/null 2>&1; then
        echo "  ✓ $LABEL"
    fi
}

check_kmp_dep "kotlinx-coroutines" "kotlinx-coroutines (KMP-ready)"
check_kmp_dep "kotlinx-serialization" "kotlinx-serialization (KMP-ready)"
check_kmp_dep "kotlinx-datetime" "kotlinx-datetime (KMP-ready)"
check_kmp_dep "ktor" "Ktor (KMP-ready)"
check_kmp_dep "koin" "Koin (KMP-ready)"
check_kmp_dep "coil3\|coil-compose" "Coil 3 (KMP-ready)"
check_kmp_dep "sqldelight" "SQLDelight (KMP-ready)"

echo ""

# --- Module Structure ---
echo "----------------------------------------"
echo " Module Structure"
echo "----------------------------------------"

BUILD_FILES=$(find "$PROJECT_ROOT" -name "build.gradle.kts" -o -name "build.gradle" | grep -v '.gradle/' | grep -v 'build/' | sort)

MODULE_COUNT=0
KMP_COUNT=0
ANDROID_APP_COUNT=0
ANDROID_LIB_COUNT=0

for BUILD_FILE in $BUILD_FILES; do
    MODULE_DIR=$(dirname "$BUILD_FILE")
    REL_MODULE=$(echo "$MODULE_DIR" | sed "s|$PROJECT_ROOT||" | sed 's|^/||')

    if [ -z "$REL_MODULE" ]; then
        MODULE_NAME="(root)"
    else
        MODULE_NAME=":$(echo "$REL_MODULE" | sed 's|/|:|g')"
        MODULE_COUNT=$((MODULE_COUNT + 1))
    fi

    IS_KMP="no"
    IS_APP="no"
    IS_LIB="no"

    if grep -q 'kotlin.multiplatform\|kotlin("multiplatform")\|kotlinMultiplatform' "$BUILD_FILE" 2>/dev/null; then
        IS_KMP="yes"
        KMP_COUNT=$((KMP_COUNT + 1))
    fi
    if grep -q 'com.android.application\|androidApplication' "$BUILD_FILE" 2>/dev/null; then
        if ! grep -q 'apply false' "$BUILD_FILE" 2>/dev/null; then
            IS_APP="yes"
            ANDROID_APP_COUNT=$((ANDROID_APP_COUNT + 1))
        fi
    fi
    if grep -q 'com.android.library\|androidLibrary' "$BUILD_FILE" 2>/dev/null; then
        if ! grep -q 'apply false' "$BUILD_FILE" 2>/dev/null; then
            IS_LIB="yes"
            ANDROID_LIB_COUNT=$((ANDROID_LIB_COUNT + 1))
        fi
    fi

    # Skip root buildscript
    [ "$MODULE_NAME" = "(root)" ] && continue

    # Determine source layout
    LAYOUT=""
    [ -d "$MODULE_DIR/src/commonMain" ] && LAYOUT="KMP"
    [ -d "$MODULE_DIR/src/main" ] && LAYOUT="${LAYOUT:+$LAYOUT + }Android"

    TYPE=""
    [ "$IS_APP" = "yes" ] && TYPE="app"
    [ "$IS_LIB" = "yes" ] && TYPE="${TYPE:+$TYPE + }library"
    [ "$IS_KMP" = "yes" ] && TYPE="${TYPE:+$TYPE + }KMP"
    [ -z "$TYPE" ] && TYPE="other"

    echo "  $MODULE_NAME ($TYPE) ${LAYOUT:+[layout: $LAYOUT]}"
done

echo ""
echo "  Total modules: $MODULE_COUNT"
echo "  Already KMP: $KMP_COUNT"
echo "  Android app modules: $ANDROID_APP_COUNT"
echo "  Android library modules: $ANDROID_LIB_COUNT"
echo "  Candidates for KMP: $((ANDROID_LIB_COUNT))"
echo ""

# --- Versions ---
echo "----------------------------------------"
echo " Versions"
echo "----------------------------------------"

if [ -f "$TOML_FILE" ]; then
    AGP_VERSION=$(grep '^agp' "$TOML_FILE" | head -1 | sed 's/.*= *"//' | sed 's/".*//')
    KOTLIN_VERSION=$(grep '^kotlin' "$TOML_FILE" | head -1 | sed 's/.*= *"//' | sed 's/".*//')
    COMPOSE_VERSION=$(grep -i '^compose' "$TOML_FILE" | head -1 | sed 's/.*= *"//' | sed 's/".*//')

    [ -n "$AGP_VERSION" ] && echo "  AGP: $AGP_VERSION"
    [ -n "$KOTLIN_VERSION" ] && echo "  Kotlin: $KOTLIN_VERSION"
    [ -n "$COMPOSE_VERSION" ] && echo "  Compose: $COMPOSE_VERSION"
else
    echo "  No version catalog found; check build files for versions"
fi

WRAPPER_PROPS="$PROJECT_ROOT/gradle/wrapper/gradle-wrapper.properties"
if [ -f "$WRAPPER_PROPS" ]; then
    GRADLE_VERSION=$(grep 'distributionUrl' "$WRAPPER_PROPS" | sed 's|.*gradle-||' | sed 's|-.*||')
    echo "  Gradle: $GRADLE_VERSION"
fi
echo ""

# --- Summary ---
echo "========================================"
echo " Readiness Summary"
echo "========================================"
echo ""

BLOCKERS=0
WARNINGS=0

if [ "$JAVA_COUNT" -gt 5 ]; then
    echo "  ✗ BLOCKER: Significant Java code needs conversion to Kotlin"
    BLOCKERS=$((BLOCKERS + 1))
elif [ "$JAVA_COUNT" -gt 0 ]; then
    echo "  ⚠ WARNING: Some Java files need conversion"
    WARNINGS=$((WARNINGS + 1))
fi

if [ "$VIEW_COUNT" -gt 0 ] || [ "$LAYOUT_COUNT" -gt 0 ]; then
    echo "  ⚠ WARNING: Android Views detected — UI sharing requires Compose migration"
    WARNINGS=$((WARNINGS + 1))
fi

if grep -rl "dagger\|hilt" "$PROJECT_ROOT" --include="*.kts" --include="*.gradle" --include="*.toml" 2>/dev/null | grep -v '/build/' | grep -v '/.gradle/' > /dev/null 2>&1; then
    echo "  ⚠ WARNING: Hilt/Dagger needs migration to Koin or Metro"
    WARNINGS=$((WARNINGS + 1))
fi

if grep -rl "rxjava\|rxkotlin" "$PROJECT_ROOT" --include="*.kts" --include="*.gradle" --include="*.toml" 2>/dev/null | grep -v '/build/' | grep -v '/.gradle/' > /dev/null 2>&1; then
    echo "  ⚠ WARNING: RxJava needs migration to coroutines/Flow"
    WARNINGS=$((WARNINGS + 1))
fi

if [ "$BLOCKERS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
    echo "  ✓ Project appears ready for KMP migration"
elif [ "$BLOCKERS" -eq 0 ]; then
    echo ""
    echo "  $WARNINGS warning(s) — address these before or during migration"
else
    echo ""
    echo "  $BLOCKERS blocker(s), $WARNINGS warning(s) — resolve blockers first"
fi

echo ""
echo "========================================"
echo " Run the migration skill for guided assistance."
echo "========================================"
