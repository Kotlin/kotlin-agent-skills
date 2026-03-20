# Kotlin in Maven - Verification Checklist

Use this checklist after configuring Kotlin in a Maven project.

## Build Configuration

- [ ] `kotlin.version` property defined in `<properties>`
- [ ] `kotlin-maven-plugin` in `<build><plugins>` (not just in `<pluginManagement>`)
- [ ] `<extensions>true</extensions>` set on the Kotlin plugin
- [ ] No explicit `kotlin-stdlib` dependency (managed by extensions)

## Test Dependencies

- [ ] `junit-jupiter-engine` present with `<scope>test</scope>` (if using JUnit 5)
- [ ] `kotlin-test` present if using Kotlin-specific test assertions (optional)

## Compilation

- [ ] `./mvnw clean compile` succeeds
- [ ] Kotlin production files in `src/main/java` or `src/main/kotlin` compile
- [ ] Java code can reference Kotlin classes
- [ ] Kotlin code can reference Java classes

## Tests

- [ ] `./mvnw clean test` succeeds
- [ ] Kotlin test files in `src/test/java` or `src/test/kotlin` are found and executed
- [ ] Both Java and Kotlin tests pass
- [ ] Test report shows all expected test classes

## Multi-Module (If Applicable)

- [ ] Each module that needs Kotlin has the plugin configured
- [ ] Or parent POM has the plugin and child modules inherit it
- [ ] Cross-module references between Java and Kotlin work
