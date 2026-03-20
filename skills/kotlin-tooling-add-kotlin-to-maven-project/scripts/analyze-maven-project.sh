#!/bin/sh
#
# analyze-maven-project.sh - Analyze a Maven project for Kotlin configuration readiness
#
# Usage: ./analyze-maven-project.sh [PROJECT_ROOT]
#        Defaults to current directory if PROJECT_ROOT is not specified.

set -e

PROJECT_ROOT="${1:-.}"

# Resolve to absolute path
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"

echo "========================================"
echo " Kotlin in Maven - Project Analysis"
echo "========================================"
echo ""
echo "Project root: $PROJECT_ROOT"
echo ""

# --- POM Detection ---
POM_FILE="$PROJECT_ROOT/pom.xml"
if [ ! -f "$POM_FILE" ]; then
    echo "ERROR: No pom.xml found in $PROJECT_ROOT"
    exit 1
fi

# --- Multi-Module Check ---
echo "----------------------------------------"
echo " Project Structure"
echo "----------------------------------------"
MODULE_POMS=$(find "$PROJECT_ROOT" -name "pom.xml" -not -path "*/target/*" -not -path "*/.mvn/*" | sort)
MODULE_COUNT=$(echo "$MODULE_POMS" | wc -l | tr -d ' ')
echo "  POM files found: $MODULE_COUNT"

if [ "$MODULE_COUNT" -gt 1 ]; then
    echo "  Type: Multi-module project"
    echo "  Modules:"
    for POM in $MODULE_POMS; do
        REL=$(echo "$POM" | sed "s|$PROJECT_ROOT/||")
        echo "    - $REL"
    done
else
    echo "  Type: Single-module project"
fi
echo ""

# --- Analyze Each POM ---
for POM in $MODULE_POMS; do
    REL_PATH=$(echo "$POM" | sed "s|$PROJECT_ROOT/||")
    MODULE_DIR=$(dirname "$POM")

    echo "----------------------------------------"
    echo " Module: $REL_PATH"
    echo "----------------------------------------"

    # Check Java version
    JAVA_VERSION=""
    if grep -q 'maven.compiler.release' "$POM"; then
        JAVA_VERSION=$(grep 'maven.compiler.release' "$POM" | sed 's/.*>\([^<]*\)<.*/\1/' | head -1)
        echo "  Java version (compiler.release): $JAVA_VERSION"
    elif grep -q 'maven.compiler.source' "$POM"; then
        JAVA_VERSION=$(grep 'maven.compiler.source' "$POM" | sed 's/.*>\([^<]*\)<.*/\1/' | head -1)
        echo "  Java version (compiler.source): $JAVA_VERSION"
    fi

    # Check for Kotlin version property
    HAS_KOTLIN_VERSION="no"
    if grep -q 'kotlin.version' "$POM"; then
        KOTLIN_VERSION=$(grep 'kotlin.version' "$POM" | sed 's/.*>\([^<]*\)<.*/\1/' | head -1)
        echo "  Kotlin version property: $KOTLIN_VERSION"
        HAS_KOTLIN_VERSION="yes"
    else
        echo "  Kotlin version property: not found"
    fi

    # Check for kotlin-maven-plugin
    HAS_KOTLIN_PLUGIN="no"
    HAS_EXTENSIONS="no"
    IN_PLUGIN_MGMT="no"
    if grep -q 'kotlin-maven-plugin' "$POM"; then
        HAS_KOTLIN_PLUGIN="yes"
        if grep -A5 'kotlin-maven-plugin' "$POM" | grep -q '<extensions>true</extensions>'; then
            HAS_EXTENSIONS="yes"
        fi
        # Rough check: is it inside pluginManagement?
        # This is a heuristic — XML parsing in shell is limited
        if sed -n '/<pluginManagement>/,/<\/pluginManagement>/p' "$POM" | grep -q 'kotlin-maven-plugin'; then
            IN_PLUGIN_MGMT="yes"
        fi
        echo "  kotlin-maven-plugin: found"
        echo "    extensions=true: $HAS_EXTENSIONS"
        echo "    in pluginManagement only: $IN_PLUGIN_MGMT"
    else
        echo "  kotlin-maven-plugin: not found"
    fi

    # Check for kotlin-stdlib dependency
    if grep -q 'kotlin-stdlib' "$POM"; then
        echo "  kotlin-stdlib dependency: found (can be removed if using extensions=true)"
    fi

    # Check for test dependencies
    echo "  Test dependencies:"
    if grep -q 'junit-jupiter-api' "$POM"; then
        echo "    - junit-jupiter-api: found"
    fi
    if grep -q 'junit-jupiter-engine' "$POM"; then
        echo "    - junit-jupiter-engine: found"
    else
        echo "    - junit-jupiter-engine: NOT FOUND (needed for test execution)"
    fi
    if grep -q 'junit-jupiter-params' "$POM"; then
        echo "    - junit-jupiter-params: found"
    fi
    if grep -q 'kotlin-test' "$POM"; then
        echo "    - kotlin-test: found"
    fi
    if grep -q 'junit-bom\|junit.bom' "$POM"; then
        echo "    - JUnit BOM: found"
    fi

    # Check for maven-compiler-plugin in <plugins> (not pluginManagement)
    if grep -q 'maven-compiler-plugin' "$POM"; then
        echo "  maven-compiler-plugin: found"
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

    # Check for Maven wrapper
    if [ -f "$MODULE_DIR/mvnw" ]; then
        echo "  Maven wrapper: found"
    elif [ -f "$PROJECT_ROOT/mvnw" ]; then
        echo "  Maven wrapper: found (in project root)"
    else
        echo "  Maven wrapper: not found"
    fi

    # Recommendation
    echo ""
    echo "  Recommendation:"
    if [ "$HAS_KOTLIN_PLUGIN" = "yes" ] && [ "$HAS_EXTENSIONS" = "yes" ] && [ "$IN_PLUGIN_MGMT" = "no" ]; then
        echo "    -> Kotlin plugin already configured with extensions. Project appears ready."
    elif [ "$HAS_KOTLIN_PLUGIN" = "yes" ] && [ "$HAS_EXTENSIONS" = "no" ]; then
        echo "    -> Kotlin plugin found but extensions not enabled. Add <extensions>true</extensions>."
    elif [ "$HAS_KOTLIN_PLUGIN" = "yes" ] && [ "$IN_PLUGIN_MGMT" = "yes" ]; then
        echo "    -> Kotlin plugin is in pluginManagement only. Move to <build><plugins> with extensions=true."
    else
        echo "    -> Add kotlin-maven-plugin with <extensions>true</extensions> to <build><plugins>."
        if [ "$HAS_KOTLIN_VERSION" = "no" ]; then
            echo "    -> Add <kotlin.version> property to <properties>."
        fi
    fi

    echo ""
done

# --- Summary ---
echo "========================================"
echo " Summary"
echo "========================================"
echo ""
echo "  Steps to add Kotlin:"
echo "  1. Add <kotlin.version> property (if not present)"
echo "  2. Add kotlin-maven-plugin with <extensions>true</extensions>"
echo "  3. Add junit-jupiter-engine dependency (if running tests)"
echo "  4. Place .kt files in src/main/java or src/main/kotlin"
echo "  5. Run: ./mvnw clean test"
echo ""
echo "========================================"
