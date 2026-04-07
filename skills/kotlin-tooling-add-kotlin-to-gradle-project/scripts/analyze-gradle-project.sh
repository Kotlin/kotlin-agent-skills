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
    echo "  Root build file: none (submodule-only project, common in Gradle 9+)"
fi

if [ -n "$BUILD_FILE" ]; then
    echo "  Build file: $(basename "$BUILD_FILE") ($DSL_TYPE)"
fi
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
    INCLUDES=$(grep -E 'include\s*\(|include\s+' "$SETTINGS_FILE" 2>/dev/null | grep -v '//' | grep -v '*' || true)
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

    # Check for java.toolchain.languageVersion
    HAS_JAVA_TOOLCHAIN="no"
    if grep -qE 'toolchain\s*\{|languageVersion\.set|languageVersion\s*=' "$BUILD"; then
        HAS_JAVA_TOOLCHAIN="yes"
        GLOBAL_HAS_JAVA_TOOLCHAIN="yes"
        JAVA_TOOLCHAIN_VER=$(grep -oE 'JavaLanguageVersion\.of\(([0-9]+)\)' "$BUILD" | sed 's/.*(\([0-9]*\)).*/\1/' | head -1)
        if [ -n "$JAVA_TOOLCHAIN_VER" ]; then
            echo "  java.toolchain.languageVersion: $JAVA_TOOLCHAIN_VER (Kotlin plugin will inherit this — do NOT add jvmToolchain)"
        else
            echo "  java.toolchain: configured (Kotlin plugin will inherit this — do NOT add jvmToolchain)"
        fi
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

    # Detect frameworks that require compiler plugins
    NEEDS_SPRING="no"
    NEEDS_JPA="no"
    if grep -qE 'org\.springframework\.boot|spring-boot-starter|spring-context|spring-web|spring-webflux' "$BUILD"; then
        NEEDS_SPRING="yes"
        GLOBAL_NEEDS_SPRING="yes"
    fi
    if grep -qE 'spring-boot-starter-data-jpa|jakarta\.persistence|javax\.persistence|hibernate-core' "$BUILD"; then
        NEEDS_JPA="yes"
        GLOBAL_NEEDS_JPA="yes"
    fi

    # Report framework detection and missing plugins
    if [ "$NEEDS_SPRING" = "yes" ]; then
        if echo "$COMPILER_PLUGINS" | grep -q 'spring'; then
            echo "  Spring framework: detected (plugin.spring already applied)"
        else
            echo "  Spring framework: DETECTED — kotlin(\"plugin.spring\") MUST be added"
        fi
    fi
    if [ "$NEEDS_JPA" = "yes" ]; then
        if echo "$COMPILER_PLUGINS" | grep -q 'jpa'; then
            echo "  JPA: detected (plugin.jpa already applied)"
        else
            echo "  JPA: DETECTED — kotlin(\"plugin.jpa\") MUST be added"
        fi
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
    if [ "$HAS_KOTLIN_JVM" = "yes" ] && ([ "$HAS_TOOLCHAIN" = "yes" ] || [ "$HAS_JAVA_TOOLCHAIN" = "yes" ]); then
        echo "    -> Kotlin JVM plugin already configured. Project appears ready."
    elif [ "$HAS_KOTLIN_JVM" = "yes" ] && [ "$HAS_TOOLCHAIN" = "no" ] && [ "$HAS_JAVA_TOOLCHAIN" = "no" ]; then
        echo "    -> Kotlin plugin found but jvmToolchain not set. Add kotlin { jvmToolchain(N) }."
    else
        echo "    -> Add kotlin(\"jvm\") plugin to the plugins {} block."
        if [ "$HAS_JAVA_TOOLCHAIN" = "yes" ]; then
            echo "    -> java.toolchain.languageVersion is set — do NOT add kotlin { jvmToolchain(N) }."
        else
            echo "    -> Add kotlin { jvmToolchain(N) } matching your Java version."
        fi
        if [ "$HAS_KOTLIN_TEST" = "no" ]; then
            echo "    -> Add testImplementation(kotlin(\"test\")) to dependencies."
        fi
    fi
    if [ "$NEEDS_SPRING" = "yes" ] && ! echo "$COMPILER_PLUGINS" | grep -q 'spring'; then
        echo "    -> Add kotlin(\"plugin.spring\") — required for Spring classes to work with Kotlin."
    fi
    if [ "$NEEDS_JPA" = "yes" ] && ! echo "$COMPILER_PLUGINS" | grep -q 'jpa'; then
        echo "    -> Add kotlin(\"plugin.jpa\") — required for JPA entities in Kotlin."
    fi

    echo ""
}

# Track global flags across all modules for the summary
GLOBAL_HAS_JAVA_TOOLCHAIN="no"
GLOBAL_NEEDS_SPRING="no"
GLOBAL_NEEDS_JPA="no"

# Analyze root build file
if [ -n "$BUILD_FILE" ]; then
    analyze_build_file "$BUILD_FILE"
else
    echo "----------------------------------------"
    echo " Root: no build file (submodule-only project)"
    echo "----------------------------------------"
    echo ""
fi

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
STEP=0
next_step() { STEP=$((STEP + 1)); }

echo "  Steps to add Kotlin:"
next_step; echo "  $STEP. Add kotlin(\"jvm\") plugin to the plugins {} block"
if [ "$GLOBAL_HAS_JAVA_TOOLCHAIN" = "yes" ]; then
    next_step; echo "  $STEP. java.toolchain.languageVersion is already set — do NOT add kotlin { jvmToolchain(N) }"
else
    next_step; echo "  $STEP. Add kotlin { jvmToolchain(N) } matching your Java version"
fi
next_step; echo "  $STEP. Add testImplementation(kotlin(\"test\")) to dependencies"
if [ "$GLOBAL_NEEDS_SPRING" = "yes" ]; then
    next_step; echo "  $STEP. Add kotlin(\"plugin.spring\") — Spring framework detected"
fi
if [ "$GLOBAL_NEEDS_JPA" = "yes" ]; then
    next_step; echo "  $STEP. Add kotlin(\"plugin.jpa\") — JPA detected"
fi
next_step; echo "  $STEP. Place .kt files in src/main/java or src/main/kotlin"
next_step; echo "  $STEP. Run: ./gradlew clean test"
echo ""
echo "========================================"
