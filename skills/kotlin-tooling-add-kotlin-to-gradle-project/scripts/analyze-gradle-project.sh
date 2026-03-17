#!/bin/sh
#
# analyze-gradle-project.sh - Analyze a Gradle project for Kotlin configuration readiness
#
# Usage: ./analyze-gradle-project.sh [PROJECT_ROOT]
#        Defaults to current directory if PROJECT_ROOT is not specified.

set -e

PROJECT_ROOT="${1:-.}"

# Resolve to absolute path
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"

echo "========================================"
echo " Kotlin in Gradle - Project Analysis"
echo "========================================"
echo ""
echo "Project root: $PROJECT_ROOT"
echo ""

# --- Build File Detection ---
BUILD_FILE=""
DSL_TYPE=""
if [ -f "$PROJECT_ROOT/build.gradle.kts" ]; then
    BUILD_FILE="$PROJECT_ROOT/build.gradle.kts"
    DSL_TYPE="Kotlin DSL"
elif [ -f "$PROJECT_ROOT/build.gradle" ]; then
    BUILD_FILE="$PROJECT_ROOT/build.gradle"
    DSL_TYPE="Groovy DSL"
else
    echo "ERROR: No build.gradle.kts or build.gradle found in $PROJECT_ROOT"
    exit 1
fi

echo "  Build file: $(basename "$BUILD_FILE") ($DSL_TYPE)"
echo ""

# --- Gradle Wrapper Version ---
echo "----------------------------------------"
echo " Gradle Version"
echo "----------------------------------------"
WRAPPER_PROPS="$PROJECT_ROOT/gradle/wrapper/gradle-wrapper.properties"
if [ -f "$WRAPPER_PROPS" ]; then
    GRADLE_URL=$(grep 'distributionUrl' "$WRAPPER_PROPS" | sed 's/.*=//' | sed 's/\\//g')
    GRADLE_VERSION=$(echo "$GRADLE_URL" | sed 's|.*gradle-||' | sed 's|-.*||')
    echo "  Distribution URL: $GRADLE_URL"
    echo "  Gradle version:   $GRADLE_VERSION"
else
    echo "  WARNING: gradle-wrapper.properties not found"
    GRADLE_VERSION="unknown"
fi
echo ""

# --- Multi-Module Check ---
echo "----------------------------------------"
echo " Project Structure"
echo "----------------------------------------"
SETTINGS_FILE=""
if [ -f "$PROJECT_ROOT/settings.gradle.kts" ]; then
    SETTINGS_FILE="$PROJECT_ROOT/settings.gradle.kts"
elif [ -f "$PROJECT_ROOT/settings.gradle" ]; then
    SETTINGS_FILE="$PROJECT_ROOT/settings.gradle"
fi

if [ -n "$SETTINGS_FILE" ]; then
    INCLUDES=$(grep 'include(' "$SETTINGS_FILE" 2>/dev/null | grep -v '//' | grep -v '*' || true)
    if [ -n "$INCLUDES" ]; then
        echo "  Type: Multi-module project"
        echo "  Includes:"
        echo "$INCLUDES" | sed 's/^/    /'
    else
        echo "  Type: Single-module project"
    fi
else
    echo "  Type: Single-module project (no settings file)"
fi
echo ""

# --- Version Catalog ---
echo "----------------------------------------"
echo " Version Catalog"
echo "----------------------------------------"
TOML_FILE="$PROJECT_ROOT/gradle/libs.versions.toml"
if [ -f "$TOML_FILE" ]; then
    echo "  Version catalog: found"
    KOTLIN_IN_CATALOG="no"
    if grep -q 'kotlin' "$TOML_FILE"; then
        KOTLIN_VERSION=$(grep -E '^kotlin\s*=' "$TOML_FILE" | sed 's/.*= *"//' | sed 's/".*//' | head -1)
        if [ -n "$KOTLIN_VERSION" ]; then
            echo "  Kotlin version in catalog: $KOTLIN_VERSION"
            KOTLIN_IN_CATALOG="yes"
        fi
    fi
    if [ "$KOTLIN_IN_CATALOG" = "no" ]; then
        echo "  Kotlin version in catalog: not found"
    fi
else
    echo "  Version catalog: not found"
fi
echo ""

# --- Analyze Build Files ---
analyze_build_file() {
    local BUILD="$1"
    local REL_PATH=$(echo "$BUILD" | sed "s|$PROJECT_ROOT/||")
    local MODULE_DIR=$(dirname "$BUILD")

    echo "----------------------------------------"
    echo " Module: $REL_PATH"
    echo "----------------------------------------"

    # Check for Kotlin plugin
    HAS_KOTLIN_JVM="no"
    if grep -qE 'kotlin\("jvm"\)|org\.jetbrains\.kotlin\.jvm|kotlin-jvm' "$BUILD"; then
        HAS_KOTLIN_JVM="yes"
        # Check if apply false
        if grep -qE 'kotlin.*apply\s*false|kotlin-jvm.*apply\s*false' "$BUILD"; then
            echo "  kotlin(\"jvm\") plugin: declared with apply false (root declaration)"
        else
            echo "  kotlin(\"jvm\") plugin: applied"
        fi
    else
        echo "  kotlin(\"jvm\") plugin: not found"
    fi

    # Check for jvmToolchain
    HAS_TOOLCHAIN="no"
    if grep -q 'jvmToolchain' "$BUILD"; then
        TOOLCHAIN_VERSION=$(grep 'jvmToolchain' "$BUILD" | sed 's/.*jvmToolchain(\([0-9]*\)).*/\1/' | head -1)
        echo "  jvmToolchain: $TOOLCHAIN_VERSION"
        HAS_TOOLCHAIN="yes"
    else
        echo "  jvmToolchain: not configured"
    fi

    # Check Java version
    if grep -q 'sourceCompatibility' "$BUILD"; then
        JAVA_VER=$(grep 'sourceCompatibility' "$BUILD" | sed 's/.*VERSION_//' | sed 's/".*//' | sed "s/'.*//" | head -1)
        echo "  Java sourceCompatibility: $JAVA_VER"
    fi

    # Check for kotlin-test dependency
    HAS_KOTLIN_TEST="no"
    if grep -qE 'kotlin\("test"\)|kotlin-test' "$BUILD"; then
        HAS_KOTLIN_TEST="yes"
        echo "  kotlin(\"test\") dependency: found"
    else
        echo "  kotlin(\"test\") dependency: not found"
    fi

    # Check for useJUnitPlatform
    if grep -q 'useJUnitPlatform' "$BUILD"; then
        echo "  useJUnitPlatform(): configured"
    else
        echo "  useJUnitPlatform(): NOT FOUND (needed for JUnit 5 test discovery)"
    fi

    # Check for kotlin-stdlib dependency
    if grep -q 'kotlin-stdlib' "$BUILD"; then
        echo "  kotlin-stdlib dependency: found (can be removed — plugin manages it automatically)"
    fi

    # Check for compiler plugins
    COMPILER_PLUGINS=""
    if grep -qE 'kotlin\("plugin\.spring"\)|plugin\.spring' "$BUILD"; then
        COMPILER_PLUGINS="$COMPILER_PLUGINS spring"
    fi
    if grep -qE 'kotlin\("plugin\.jpa"\)|plugin\.jpa' "$BUILD"; then
        COMPILER_PLUGINS="$COMPILER_PLUGINS jpa"
    fi
    if grep -qE 'kotlin\("plugin\.serialization"\)|plugin\.serialization' "$BUILD"; then
        COMPILER_PLUGINS="$COMPILER_PLUGINS serialization"
    fi
    if [ -n "$COMPILER_PLUGINS" ]; then
        echo "  Compiler plugins:$COMPILER_PLUGINS"
    fi

    # Check source directory layout
    echo "  Source directories:"
    [ -d "$MODULE_DIR/src/main/java" ] && echo "    - src/main/java: exists"
    [ -d "$MODULE_DIR/src/main/kotlin" ] && echo "    - src/main/kotlin: exists"
    [ -d "$MODULE_DIR/src/test/java" ] && echo "    - src/test/java: exists"
    [ -d "$MODULE_DIR/src/test/kotlin" ] && echo "    - src/test/kotlin: exists"

    # Check for .kt files
    KT_MAIN=$(find "$MODULE_DIR/src/main" -name "*.kt" 2>/dev/null | wc -l | tr -d ' ')
    KT_TEST=$(find "$MODULE_DIR/src/test" -name "*.kt" 2>/dev/null | wc -l | tr -d ' ')
    JAVA_MAIN=$(find "$MODULE_DIR/src/main" -name "*.java" 2>/dev/null | wc -l | tr -d ' ')
    JAVA_TEST=$(find "$MODULE_DIR/src/test" -name "*.java" 2>/dev/null | wc -l | tr -d ' ')
    echo "  File counts:"
    echo "    - Java production files: $JAVA_MAIN"
    echo "    - Java test files: $JAVA_TEST"
    echo "    - Kotlin production files: $KT_MAIN"
    echo "    - Kotlin test files: $KT_TEST"

    # Gradle wrapper
    if [ -f "$MODULE_DIR/gradlew" ]; then
        echo "  Gradle wrapper: found"
    elif [ -f "$PROJECT_ROOT/gradlew" ]; then
        echo "  Gradle wrapper: found (in project root)"
    else
        echo "  Gradle wrapper: not found"
    fi

    # Recommendation
    echo ""
    echo "  Recommendation:"
    if [ "$HAS_KOTLIN_JVM" = "yes" ] && [ "$HAS_TOOLCHAIN" = "yes" ]; then
        echo "    -> Kotlin JVM plugin already configured. Project appears ready."
    elif [ "$HAS_KOTLIN_JVM" = "yes" ] && [ "$HAS_TOOLCHAIN" = "no" ]; then
        echo "    -> Kotlin plugin found but jvmToolchain not set. Add kotlin { jvmToolchain(N) }."
    else
        echo "    -> Add kotlin(\"jvm\") plugin to the plugins {} block."
        echo "    -> Add kotlin { jvmToolchain(N) } matching your Java version."
        if [ "$HAS_KOTLIN_TEST" = "no" ]; then
            echo "    -> Add testImplementation(kotlin(\"test\")) to dependencies."
        fi
    fi

    echo ""
}

# Analyze root build file
analyze_build_file "$BUILD_FILE"

# Analyze submodule build files
SUBMODULE_BUILDS=$(find "$PROJECT_ROOT" -mindepth 2 \( -name "build.gradle.kts" -o -name "build.gradle" \) | grep -v '.gradle/' | grep -v 'build/' | grep -v 'buildSrc/' | sort || true)
for SUB_BUILD in $SUBMODULE_BUILDS; do
    analyze_build_file "$SUB_BUILD"
done

# --- Summary ---
echo "========================================"
echo " Summary"
echo "========================================"
echo ""
echo "  Steps to add Kotlin:"
echo "  1. Add kotlin(\"jvm\") plugin to the plugins {} block"
echo "  2. Add kotlin { jvmToolchain(N) } matching your Java version"
echo "  3. Add testImplementation(kotlin(\"test\")) to dependencies"
echo "  4. Place .kt files in src/main/java or src/main/kotlin"
echo "  5. Run: ./gradlew clean test"
echo ""
echo "========================================"
