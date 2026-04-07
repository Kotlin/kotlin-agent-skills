# Kotlin in Gradle - Verification Checklist

Use this checklist after configuring Kotlin in a Gradle project.

## Build Configuration

- [ ] `kotlin("jvm")` plugin applied in `build.gradle.kts` (not just declared with `apply false`)
- [ ] JVM toolchain configured: either `kotlin { jvmToolchain(N) }` set, OR project already has `java.toolchain.languageVersion` (do not add both)
- [ ] No explicit `kotlin-stdlib` dependency (managed by the plugin automatically)
- [ ] `mavenCentral()` in `repositories {}` block

## Compiler Plugins (Framework Detection)

- [ ] If project uses Spring (`spring-boot-starter-*`, Spring plugin): `kotlin("plugin.spring")` applied
- [ ] If project uses JPA (`spring-boot-starter-data-jpa`, `jakarta.persistence`, `hibernate-core`): `kotlin("plugin.jpa")` applied
- [ ] If project uses kotlinx-serialization: `kotlin("plugin.serialization")` applied

## Test Dependencies

- [ ] `testImplementation(kotlin("test"))` present (optional but recommended)
- [ ] `useJUnitPlatform()` set in `tasks.test {}` (required for JUnit 5 discovery)
- [ ] Test engine dependency present (`junit-jupiter-engine` as `testRuntimeOnly`)

## Compilation

- [ ] `./gradlew clean compileKotlin` succeeds
- [ ] Kotlin production files in `src/main/java` or `src/main/kotlin` compile
- [ ] Java code can reference Kotlin classes
- [ ] Kotlin code can reference Java classes

## Tests

- [ ] `./gradlew clean test` succeeds
- [ ] Kotlin test files in `src/test/java` or `src/test/kotlin` are found and executed
- [ ] Both Java and Kotlin tests pass
- [ ] Test report in `build/reports/tests/test/index.html` shows all test classes

## Multi-Module (If Applicable)

- [ ] Root `build.gradle.kts` declares plugin with `apply false`
- [ ] Each submodule that needs Kotlin applies the plugin
- [ ] `jvmToolchain` configured consistently across modules
- [ ] Cross-module references between Java and Kotlin work
