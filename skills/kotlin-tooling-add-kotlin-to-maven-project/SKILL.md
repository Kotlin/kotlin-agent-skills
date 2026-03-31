---
name: kotlin-tooling-add-kotlin-to-maven-project
description: >
  Configures Kotlin in an existing Java Maven project so that both Java and Kotlin
  source files compile together in src/main and src/test. Handles pom.xml changes
  (kotlin-maven-plugin with extensions, dependencies, properties) and verifies the
  setup compiles and tests pass. Use this skill when the user wants to add Kotlin to
  a Maven project, mix Kotlin and Java in Maven, write Kotlin tests for Java code,
  configure kotlin-maven-plugin, or set up a mixed-language Maven build. Also use
  when the user mentions "Kotlin in Maven", "Maven Kotlin plugin", "add .kt files
  to Maven project", or "kotlin-maven-plugin".
license: Apache-2.0
metadata:
  author: JetBrains
  version: "1.0.0"
---

# Add Kotlin to a Java Maven Project

This skill configures an existing Java Maven project to support both Kotlin and Java
sources. After applying it, `.kt` files can live alongside `.java` files in the same
source directories and reference each other freely.

## Step 0: Analyze the Project

Before making changes, understand what exists:

1. Read `pom.xml` (and any parent pom if it's a multi-module project)
2. Check whether a `kotlin.version` property already exists
3. Check whether `kotlin-maven-plugin` is already configured
4. Look at the existing directory layout (`src/main/java`, `src/test/java`)
5. Note the Java version (`maven.compiler.release` or `maven.compiler.source`/`target`)
6. Check for existing test framework dependencies (JUnit 5, TestNG, etc.)

If Bash is available, run `scripts/analyze-maven-project.sh` from this skill's
directory to get a structured summary.

### Decide What to Configure

| User goal | What to add |
|-----------|-------------|
| Kotlin in production code only | Kotlin plugin + kotlin-stdlib (via extensions) |
| Kotlin in test code only | Kotlin plugin + kotlin-stdlib + test dependencies |
| Kotlin in both production and test code | All of the above |

The default is to configure Kotlin for both production and test code, since the
plugin with `<extensions>true</extensions>` handles both automatically.

## Step 1: Add Kotlin Version Property

Add the `kotlin.version` property to the `<properties>` section of `pom.xml`.
Use the latest stable Kotlin version. If the property already exists, verify it
points to a recent version.

```xml
<properties>
    <!-- ... existing properties ... -->
    <kotlin.version>2.1.20</kotlin.version>
</properties>
```

Check the latest Kotlin version at https://kotlinlang.org/docs/releases.html
and use it instead of the example above if a more recent stable release exists.

## Step 2: Configure Kotlin Maven Plugin

Add the `kotlin-maven-plugin` to the `<build><plugins>` section (not inside
`<pluginManagement>`). The `<extensions>true</extensions>` setting is required
— it is what makes the mixed Java-Kotlin compilation work.

```xml
<build>
    <plugins>
        <!-- Kotlin compiler for mixed Java-Kotlin projects -->
        <plugin>
            <groupId>org.jetbrains.kotlin</groupId>
            <artifactId>kotlin-maven-plugin</artifactId>
            <version>${kotlin.version}</version>
            <extensions>true</extensions>
        </plugin>
    </plugins>
</build>
```

### What `<extensions>true</extensions>` Does

This single setting handles several things that previously required manual configuration:

- **Adds `kotlin-stdlib`** as a dependency automatically — no need to declare it
- **Registers Kotlin source directories** — both `src/main/java` and `src/main/kotlin`
  (and their test equivalents) are compiled
- **Sets compilation order** — Kotlin compiles before Java, so Java code can reference
  Kotlin classes and vice versa
- **Removes the need for `maven-compiler-plugin` configuration** — the Kotlin plugin
  takes over compilation orchestration

### Important: Plugin Placement

The `kotlin-maven-plugin` entry goes in `<build><plugins>`, not in
`<build><pluginManagement><plugins>`. The `<pluginManagement>` section only declares
default configuration — it does not activate the plugin. If the plugin is only in
`<pluginManagement>`, Kotlin files will not be compiled.

If the project has a `maven-compiler-plugin` entry in `<pluginManagement>`, it can
be left there (it does no harm), but it is not needed for the Kotlin plugin with
extensions to work. Do not add a `maven-compiler-plugin` entry to `<plugins>` — the
Kotlin plugin handles compilation.

## Step 3: Add Test Dependencies (If Needed)

If the project runs tests, ensure the test engine dependency is present. Many Java
projects include only `junit-jupiter-api` and `junit-jupiter-params` but not the
engine, which is needed at runtime to execute tests.

```xml
<dependencies>
    <!-- ... existing dependencies ... -->

    <!-- JUnit Jupiter engine is required at test runtime -->
    <dependency>
        <groupId>org.junit.jupiter</groupId>
        <artifactId>junit-jupiter-engine</artifactId>
        <scope>test</scope>
    </dependency>
</dependencies>
```

If the project uses a BOM (like `junit-bom`) in `<dependencyManagement>`, no version
tag is needed on the engine dependency — the BOM provides it.

Skip this step if the project already has `junit-jupiter-engine` or does not use JUnit.

### Kotlin-Specific Test Dependencies (Optional)

For Kotlin test code, `kotlin-test-junit5` provides idiomatic assertion functions
(`assertEquals`, `assertTrue`, etc. from `kotlin.test`) with JUnit 5 integration.
This is optional — Kotlin tests work fine with plain JUnit assertions from
`org.junit.jupiter.api.Assertions`.

Use `kotlin-test-junit5` (not plain `kotlin-test`) when the project uses JUnit 5,
because the JUnit 5 framework adapter is needed to bridge `kotlin.test` annotations
to JUnit.

```xml
<dependency>
    <groupId>org.jetbrains.kotlin</groupId>
    <artifactId>kotlin-test-junit5</artifactId>
    <version>${kotlin.version}</version>
    <scope>test</scope>
</dependency>
```

## Step 4: Directory Structure

With `<extensions>true</extensions>`, Kotlin files can be placed in two ways:

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

Both options work out of the box with the Kotlin plugin extensions. Choose based on
team preference. Option A is simpler for gradual migration. Option B provides clearer
separation.

## Step 5: Verify Configuration

Run the build and tests to confirm everything works:

```bash
./mvnw clean test
```

Expected outcome:
- Kotlin files compile without errors
- Java files can reference Kotlin classes
- Kotlin files can reference Java classes
- All tests (both Java and Kotlin) pass

If Maven wrapper is not available, use `mvn clean test` instead.

See [assets/checklist.md](assets/checklist.md) for a complete verification checklist.

## Multi-Module Maven Projects

For multi-module projects, configure Kotlin in each module that needs it. There are
two approaches:

### Approach A: Per-Module Configuration

Add the `kotlin-maven-plugin` to each module's `pom.xml` individually. Simple and
explicit.

### Approach B: Parent POM Configuration

Define the plugin in the parent POM's `<build><plugins>` section. All child modules
inherit it. Modules that don't have Kotlin files will compile normally — the Kotlin
plugin is a no-op when there are no `.kt` sources.

```xml
<!-- parent pom.xml -->
<build>
    <plugins>
        <plugin>
            <groupId>org.jetbrains.kotlin</groupId>
            <artifactId>kotlin-maven-plugin</artifactId>
            <version>${kotlin.version}</version>
            <extensions>true</extensions>
        </plugin>
    </plugins>
</build>
```

The `kotlin.version` property should be defined in the parent POM's `<properties>`.

## Kotlin Compiler Plugins (Optional)

If the project uses frameworks that require compiler plugins, add them to the
`kotlin-maven-plugin` configuration. See
[references/COMPILER-PLUGINS.md](references/COMPILER-PLUGINS.md) for details on
Spring, serialization, all-open, and no-arg plugins.

## Common Issues

### "Cannot find symbol" for Kotlin Classes from Java

The Kotlin plugin must be in `<build><plugins>`, not just in `<pluginManagement>`.
Verify that `<extensions>true</extensions>` is set.

### Tests Not Running

Ensure `junit-jupiter-engine` is in the dependencies with `<scope>test</scope>`.
Without the engine, Maven's Surefire plugin finds test classes but cannot execute them.

### Kotlin Standard Library Version Conflict

If you see version conflicts for `kotlin-stdlib`, remove any explicit `kotlin-stdlib`
dependency — the plugin with extensions manages it automatically. If a specific version
is needed (rare), declare it explicitly and ensure it matches `${kotlin.version}`.

### "Unresolved reference" in Kotlin Files

Check that the Kotlin source file is in a directory registered as a source root.
With `<extensions>true</extensions>`, `src/main/java`, `src/main/kotlin`,
`src/test/java`, and `src/test/kotlin` are all registered automatically.

### Maven Compiler Plugin Conflicts

If you see compilation errors related to Java files not finding Kotlin classes, make
sure you do not have `maven-compiler-plugin` in `<build><plugins>` (having it only
in `<pluginManagement>` for version locking is fine). The Kotlin plugin with extensions
handles the compilation lifecycle.
