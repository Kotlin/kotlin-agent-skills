---
name: kotlin-tooling-add-kotlin-to-gradle-project
description: >
  Configures Kotlin in an existing Java Gradle project so that both Java and Kotlin
  source files compile together in src/main and src/test. Handles build.gradle.kts
  changes (kotlin("jvm") plugin, jvmToolchain, test dependencies) and verifies the
  setup compiles and tests pass. Use this skill when the user wants to add Kotlin to
  a Gradle project, mix Kotlin and Java in Gradle, write Kotlin tests for Java code,
  configure Kotlin JVM plugin, or set up a mixed-language Gradle build. Also use when
  the user mentions "Kotlin in Gradle", "kotlin jvm plugin", "add .kt files to Gradle
  project", "kotlin(\"jvm\")", or "jvmToolchain".
license: Apache-2.0
metadata:
  author: JetBrains
  version: "1.0.0"
---

# Add Kotlin to a Java Gradle Project

This skill configures an existing Java Gradle project to support both Kotlin and Java
sources. After applying it, `.kt` files can live alongside `.java` files in the same
source directories and reference each other freely.

## Step 0: Analyze the Project

Before making changes, understand what exists:

1. Read `build.gradle.kts` (or `build.gradle` for Groovy DSL)
2. Check `settings.gradle.kts` for submodules
3. Check whether `kotlin("jvm")` or `org.jetbrains.kotlin.jvm` plugin is already applied
4. Look for a version catalog at `gradle/libs.versions.toml`
5. Look at the existing directory layout (`src/main/java`, `src/test/java`)
6. Note the Java version (`jvmToolchain`, `sourceCompatibility`, `JavaVersion`, or
   `java.toolchain.languageVersion`)
7. Check for existing test framework setup (`useJUnitPlatform()`, test dependencies)

If Bash is available, run `scripts/analyze-gradle-project.sh` from this skill's
directory to get a structured summary.

## Step 1: Add Kotlin JVM Plugin

Add the Kotlin JVM plugin to the `plugins {}` block in `build.gradle.kts`.

### Direct Version (Single-Module Projects)

```kotlin
plugins {
    // ... existing plugins ...
    kotlin("jvm") version "2.1.20"
}
```

Check the latest Kotlin version at https://kotlinlang.org/docs/releases.html
and use it instead of the example above if a more recent stable release exists.

### Version Catalog Approach

If the project uses a Gradle version catalog (`gradle/libs.versions.toml`), add the
Kotlin version and plugin there:

```toml
[versions]
kotlin = "2.1.20"

[plugins]
kotlin-jvm = { id = "org.jetbrains.kotlin.jvm", version.ref = "kotlin" }
```

Then reference it in `build.gradle.kts`:

```kotlin
plugins {
    // ... existing plugins ...
    alias(libs.plugins.kotlin.jvm)
}
```

### What the Plugin Does

The `kotlin("jvm")` plugin handles everything needed for mixed Java-Kotlin compilation:

- **Adds `kotlin-stdlib`** as a dependency automatically
- **Registers Kotlin source directories** — both `src/main/java` and `src/main/kotlin`
  (and their test equivalents) are compiled
- **Sets compilation order** — Kotlin compiles before Java, so Java code can reference
  Kotlin classes and vice versa

## Step 2: Configure JVM Toolchain

Set the JVM toolchain version to match the project's Java version. This ensures
Kotlin targets the same JVM version as Java code:

```kotlin
kotlin {
    jvmToolchain(17)
}
```

Use the same version number that the project already uses for Java. Common indicators
of the Java version in a Gradle project:

| Existing setting | Example | Toolchain value |
|-----------------|---------|-----------------|
| `java.sourceCompatibility` | `JavaVersion.VERSION_17` | `17` |
| `java.toolchain.languageVersion` | `JavaLanguageVersion.of(17)` | `17` |
| `sourceCompatibility` in `java {}` | `"17"` | `17` |

If a `java.toolchain.languageVersion` is already set, the Kotlin plugin picks it up
automatically and `kotlin { jvmToolchain(...) }` is not needed. But setting it
explicitly is harmless and makes the Kotlin configuration self-documenting.

## Step 3: Add Kotlin Test Dependency

Add the Kotlin test dependency to the `dependencies {}` block:

```kotlin
dependencies {
    // ... existing dependencies ...
    testImplementation(kotlin("test"))
}
```

`kotlin("test")` automatically detects JUnit 5 when `useJUnitPlatform()` is configured
in the `tasks.test` block (which most modern JUnit 5 projects have). It provides
idiomatic Kotlin assertion functions (`assertEquals`, `assertTrue`, etc. from
`kotlin.test`) and bridges `@kotlin.test.Test` to `@org.junit.jupiter.api.Test`.

This dependency is optional if you prefer to use plain JUnit assertions directly.
Kotlin test classes work fine with `org.junit.jupiter.api.Assertions` — no special
Kotlin dependency is required for basic test compilation.

### Ensure JUnit Platform is Configured

Verify the project has `useJUnitPlatform()` in its test task configuration. Most
JUnit 5 projects already have this, but if missing:

```kotlin
tasks.test {
    useJUnitPlatform()
}
```

Without this, Gradle's test runner will not discover JUnit 5 tests.

## Step 4: Directory Structure

With the Kotlin JVM plugin, Kotlin files can be placed in two ways:

### Option A: Co-located (Recommended for Gradual Adoption)

Place `.kt` files alongside `.java` files in existing directories:

```
src/
├── main/
│   └── java/           # Both .java and .kt production files
└── test/
    └── java/           # Both .java and .kt test files
```

This works because the Kotlin plugin registers `src/main/java` and `src/test/java`
as Kotlin source directories automatically.

### Option B: Separate Directories

Use dedicated `kotlin` directories for Kotlin sources:

```
src/
├── main/
│   ├── java/           # Java production files only
│   └── kotlin/         # Kotlin production files only
└── test/
    ├── java/           # Java test files only
    └── kotlin/         # Kotlin test files only
```

Both options work out of the box. Choose based on team preference. Option A is simpler
for gradual migration. Option B provides clearer separation.

## Step 5: Verify Configuration

Run the build and tests to confirm everything works:

```bash
./gradlew clean test
```

Expected outcome:
- Kotlin files compile without errors
- Java files can reference Kotlin classes
- Kotlin files can reference Java classes
- All tests (both Java and Kotlin) pass

If Gradle wrapper is not available, use `gradle clean test` instead.

See [assets/checklist.md](assets/checklist.md) for a complete verification checklist.

## Multi-Module Gradle Projects

For multi-module projects, there are two common approaches:

### Approach A: Root Plugin Declaration + Per-Module Apply

Declare the plugin in the root `build.gradle.kts` with `apply false`, then apply
it in each submodule that needs Kotlin:

```kotlin
// root build.gradle.kts
plugins {
    kotlin("jvm") version "2.1.20" apply false
}

// submodule build.gradle.kts
plugins {
    kotlin("jvm")
}

kotlin {
    jvmToolchain(17)
}
```

### Approach B: Convention Plugin

For projects with many modules, create a convention plugin in `buildSrc` or an
included build that applies the Kotlin plugin with shared configuration:

```kotlin
// buildSrc/src/main/kotlin/kotlin-conventions.gradle.kts
plugins {
    kotlin("jvm")
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    testImplementation(kotlin("test"))
}

tasks.test {
    useJUnitPlatform()
}
```

Then apply it in each submodule:

```kotlin
plugins {
    id("kotlin-conventions")
}
```

### Approach C: Subprojects Block

For simpler projects, configure Kotlin for all submodules from the root:

```kotlin
// root build.gradle.kts
plugins {
    kotlin("jvm") version "2.1.20" apply false
}

subprojects {
    apply(plugin = "org.jetbrains.kotlin.jvm")

    configure<org.jetbrains.kotlin.gradle.dsl.KotlinJvmProjectExtension> {
        jvmToolchain(17)
    }
}
```

## Kotlin Compiler Plugins (Optional)

If the project uses frameworks that require compiler plugins (Spring, JPA,
serialization), add them in the `plugins {}` block. See
[references/COMPILER-PLUGINS.md](references/COMPILER-PLUGINS.md) for details.

## Common Issues

### "Unresolved reference" for Kotlin Classes from Java

Ensure the Kotlin JVM plugin is applied (not just declared with `apply false`).
Check that `build.gradle.kts` has `kotlin("jvm")` in its `plugins {}` block.

### Tests Not Running

Verify `useJUnitPlatform()` is set in `tasks.test {}`. Without it, Gradle will not
discover JUnit 5 tests. Also check that test engine dependencies are present
(`junit-jupiter-engine` as `testRuntimeOnly`).

### Kotlin Standard Library Version Conflict

If you see version conflicts for `kotlin-stdlib`, remove any explicit `kotlin-stdlib`
dependency — the `kotlin("jvm")` plugin manages it automatically. If you need a
specific version (rare), use a resolution strategy:

```kotlin
configurations.all {
    resolutionStrategy {
        force("org.jetbrains.kotlin:kotlin-stdlib:2.1.20")
    }
}
```

### "Could not resolve org.jetbrains.kotlin:kotlin-stdlib"

Ensure `mavenCentral()` is in the `repositories {}` block.

### Groovy DSL (`build.gradle`)

If the project uses Groovy DSL instead of Kotlin DSL, the plugin syntax differs:

```groovy
plugins {
    id 'org.jetbrains.kotlin.jvm' version '2.1.20'
}

kotlin {
    jvmToolchain 17
}

dependencies {
    testImplementation 'org.jetbrains.kotlin:kotlin-test'
}
```

The Groovy DSL `kotlin("jvm")` shorthand is not available — use the full plugin ID.
