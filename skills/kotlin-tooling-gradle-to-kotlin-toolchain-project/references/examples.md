# Migration patterns

Lifted from one real migration (Gradle + Ktor + Exposed + MongoDB + Postgres service). Adapt names, scopes,
and versions.

## 1. `project.yaml`

The root module (`.`) is included by default and needs no entry.

```yaml
modules:
  - plugins/detekt
  - plugins/jib
  - plugins/ktlint
  - plugins/package
  - plugins/release

plugins:
  - ./plugins/detekt
  - ./plugins/jib
  - ./plugins/ktlint
  - ./plugins/package
  - ./plugins/release
```

## 2. Root `module.yaml` — JVM/Ktor app

`layout: maven-like` keeps `src/main/kotlin` and friends where Gradle had them. `release`/`ktlint`/`package`
use the `enabled` shorthand; `jib`/`detekt` must use the long form because they carry settings.

```yaml
product: jvm/app

layout: maven-like

repositories:
  - id: jitpack
    url: https://jitpack.io

plugins:
  release: enabled
  jib:
    enabled: true
    container:
      mainClass: io.example.App
      jvmArgs: ["-Xms256m", "-Xmx512m"]
      ports: ["8080"]
      user: "1000"
      environment:
        SERVICE_PROFILE: "prod"
    baseImage:
      fullName: eclipse-temurin:21-jre-alpine
    targetImage:
      name: registry.example.com/team/service
      tags: ["latest"]
  detekt:
    enabled: true
    configFile: detekt.yml          # module-relative; ${...} interpolation is NOT supported here
    buildUponDefaultConfig: true
    rulesetClasspath:
      - $libs.detekt.rules
  ktlint: enabled
  package: enabled

settings:
  jvm:
    mainClass: io.example.App
    jdk:
      version: 21
  kotlin:
    serialization: json
    freeCompilerArgs: ["-Xskip-metadata-version-check"]

dependencies:
  - $libs.arrow.core
  - $libs.ktor.server.core
  - $libs.ktor.server.netty
  - $libs.ktor.server.content.negotiation
  - $libs.ktor.serialization.kotlinx.json
  # ... database / config / logging libs ...

test-dependencies:
  - $libs.kotest.runner.junit5
  - $libs.kotest.assertions.core
  - $libs.ktor.server.test.host
  - $libs.testcontainers.mongodb
  - $libs.testcontainers.postgresql
  - $libs.mockk
```

## 3. Stub `build.gradle.kts` for Dependabot

```kotlin
// Intentionally empty. Built with the Kotlin Toolchain, not Gradle; versions live in
// gradle/libs.versions.toml, consumed natively as the $libs.* catalog. This file exists only
// so Dependabot's `package-ecosystem: gradle` detector finds the project. See .github/dependabot.yml.
```

Dependabot gates on `SUPPORTED_BUILD_FILE_NAMES = %w(build.gradle build.gradle.kts)` —
<https://github.com/dependabot/dependabot-core/blob/main/gradle/lib/dependabot/gradle/file_fetcher.rb>.

## 4. `.sdkmanrc`

The value must match `kotlin_cli_version=…` at the top of the `kotlin` wrapper.

```
# Enable auto-env through the sdkman_auto_env config
java=21.0.7-tem
kotlintoolchain=0.11.0
```

## 5. `gradle/libs.versions.toml` cleanup

Remove the whole `[plugins]` block and any `[versions]` key that only fed it (`kotlin`,
`axion-release-plugin`, `jib-plugin`, `ktlint-plugin`, `detekt-plugin`). Then add entries for every
coordinate the local plugins use, so Dependabot tracks them:

```toml
# Linters
detekt = "1.23.8"
detekt-rules = "1.0.1"
ktlint = "1.5.0"

# Local plugin runtime
jib-core = "0.28.1"
jgit = "7.0.0.202409031743-r"
# Contemporary with MINA SSHD 2.13.x (what jgit 7.0.0 ships against); without bouncycastle
# on the runtime classpath, SSH push fails with NoClassDefFoundError.
bouncycastle = "1.78.1"
slf4j = "2.0.13"

[libraries]
detekt-cli = { module = "io.gitlab.arturbosch.detekt:detekt-cli", version.ref = "detekt" }
detekt-rules = { module = "com.github.marc0der:detekt-rules", version.ref = "detekt-rules" }
ktlint-cli = { module = "com.pinterest.ktlint:ktlint-cli", version.ref = "ktlint" }
jib-core = { module = "com.google.cloud.tools:jib-core", version.ref = "jib-core" }
jgit = { module = "org.eclipse.jgit:org.eclipse.jgit", version.ref = "jgit" }
jgit-ssh-apache = { module = "org.eclipse.jgit:org.eclipse.jgit.ssh.apache", version.ref = "jgit" }
bouncycastle-bcprov = { module = "org.bouncycastle:bcprov-jdk18on", version.ref = "bouncycastle" }
bouncycastle-bcpkix = { module = "org.bouncycastle:bcpkix-jdk18on", version.ref = "bouncycastle" }
slf4j-nop = { module = "org.slf4j:slf4j-nop", version.ref = "slf4j" }
```

### `[bundles]` → module templates

`$libs.bundles.*` doesn't exist. Each bundle with 2+ consumers becomes a root-level
`<name>.module-template.yaml` that also carries the settings, test deps, and repositories that used to sit
next to the bundle in `build.gradle.kts`. Delete the `[bundles]` block afterwards.

```toml
# gradle/libs.versions.toml — before
[bundles]
ktor-server = ["ktor-server-core", "ktor-server-netty", "ktor-server-content-negotiation",
               "ktor-serialization-kotlinx-json"]
exposed = ["exposed-core", "exposed-jdbc", "exposed-java-time"]
testing = ["kotest-runner-junit5", "kotest-assertions-core", "mockk"]
```

```yaml
# ktor-server.module-template.yaml
dependencies:
  - $libs.ktor.server.core
  - $libs.ktor.server.netty
  - $libs.ktor.server.content.negotiation
  - $libs.ktor.serialization.kotlinx.json

settings:
  kotlin:
    serialization: json      # the bundle's companion configuration, not just its coordinates

test-dependencies:
  - $libs.ktor.server.test.host
```

```yaml
# persistence.module-template.yaml
dependencies:
  - $libs.exposed.core
  - $libs.exposed.jdbc
  - $libs.exposed.java.time

test-dependencies:
  - $libs.testcontainers.postgresql
```

```yaml
# testing.module-template.yaml — test-only bundles are templates too
test-dependencies:
  - $libs.kotest.runner.junit5
  - $libs.kotest.assertions.core
  - $libs.mockk
```

```yaml
# service.module-template.yaml — nested: one line for "our standard service"
apply:
  - //ktor-server.module-template.yaml
  - //persistence.module-template.yaml
  - //testing.module-template.yaml

settings:
  jvm:
    jdk:
      version: 21
```

```yaml
# services/orders/module.yaml
product: jvm/app

layout: maven-like

apply:
  - //service.module-template.yaml

settings:
  jvm:
    mainClass: io.example.orders.App   # module.yaml wins over anything a template sets

dependencies:
  - $libs.arrow.core                   # appended to the template's list
```

Check the result with `./kotlin show dependencies -m orders` and diff it against the Gradle build's
configuration — a missing template `apply:` looks exactly like a dropped bundle.

## 6. The smallest plugin: `package`

Stages the application JAR at `${module.rootDir}/build/libs/${module.name}.jar` — the stable path Gradle's
`application` plugin used to publish, so CI never touches Toolchain internals
(`build/tasks/_<module>_jarJvm/<module>-jvm.jar`). `${module.jar}` auto-wires the `:jarJvm` dependency, so
`./kotlin do package` builds the JAR first.

```yaml
# plugins/package/module.yaml
product: jvm/amper-plugin

description: Stages the application JAR at build/libs/${module.name}.jar for CI artifact uploads.

pluginInfo:
  settingsClass: io.example.amper.plugins.pkg.Settings

settings:
  jvm:
    jdk:
      version: 21
  kotlin:
    languageVersion: 2.1
```

```kotlin
// plugins/package/src/Settings.kt
package io.example.amper.plugins.pkg

import org.jetbrains.amper.plugins.Configurable

@Configurable
interface Settings {
    /** File name of the staged JAR, without extension. Defaults to the module name. */
    val artifactName: String?
}
```

```kotlin
// plugins/package/src/PackageApplication.kt
package io.example.amper.plugins.pkg

import org.jetbrains.amper.plugins.CompilationArtifact
import org.jetbrains.amper.plugins.Input
import org.jetbrains.amper.plugins.Output
import org.jetbrains.amper.plugins.TaskAction
import java.nio.file.Path
import kotlin.io.path.copyTo
import kotlin.io.path.createParentDirectories

@TaskAction
fun packageApplication(
    @Input jar: CompilationArtifact,
    @Output outputJar: Path,
) {
    jar.artifact.copyTo(outputJar.createParentDirectories(), overwrite = true)
}
```

```yaml
# plugins/package/plugin.yaml
tasks:
  package:
    action: !io.example.amper.plugins.pkg.packageApplication
      jar: ${module.jar}                                            # CompilationArtifact; auto-wires jarJvm
      outputJar: ${module.rootDir}/build/libs/${module.name}.jar     # project-relative @Output

commands:
  - name: package
    performedBy: package
```

## 7. Detekt `useTypeResolution` patch

Gates the vendored plugin's unconditional `--classpath` behind an opt-in so the default matches Gradle's
default `detekt` task.

```kotlin
// plugins/detekt/src/Settings.kt
@Configurable
interface Settings {
    val configFile: Path?
    val buildUponDefaultConfig: Boolean get() = false

    /**
     * Run detekt with type resolution (passes the module's compile classpath via `--classpath`).
     * Type-resolution rules include known false positives (notably `UnreachableCode`), so this
     * defaults to `false` to match the Gradle detekt plugin's default task. Set `true` to opt in.
     */
    val useTypeResolution: Boolean get() = false

    /** Extra rule-set jars, loaded via `--plugins`. */
    val rulesetClasspath: Classpath
}
```

```kotlin
// plugins/detekt/src/runDetekt.kt — inside the args-building block
if (commonParameters.settings.useTypeResolution) {
    val cp = commonParameters.moduleClasspath.resolvedFiles
    if (cp.isNotEmpty()) {
        add("--classpath")
        add(cp.joinToString(File.pathSeparator))
    }
}
```

## 8. Preserving a legacy `release.properties` contract

If application source already reads its version from `release.properties` (key=value), add a sibling task
that writes that exact format instead of changing the source.

```kotlin
// plugins/release/src/tasks/WriteReleaseProperties.kt
package io.example.release.tasks

import org.jetbrains.amper.plugins.ExecutionAvoidance
import org.jetbrains.amper.plugins.Input
import org.jetbrains.amper.plugins.Output
import org.jetbrains.amper.plugins.TaskAction
import java.nio.file.Path
import kotlin.io.path.ExperimentalPathApi
import kotlin.io.path.createParentDirectories
import kotlin.io.path.deleteRecursively
import kotlin.io.path.div
import kotlin.io.path.writeText

@OptIn(ExperimentalPathApi::class)
@TaskAction(executionAvoidance = ExecutionAvoidance.Disabled)
fun writeReleaseProperties(
    @Input(inferTaskDependency = false) moduleRootDir: Path,
    @Output outputDir: Path,
    settings: Settings,
) {
    val pipeline = VersionPipeline(settings)
    val inferred = GitRepo.open(moduleRootDir, settings.repoDir).use { pipeline.infer(it) }

    outputDir.deleteRecursively()
    val propertiesFile = outputDir / "release.properties"
    propertiesFile.createParentDirectories()
    propertiesFile.writeText("release=${inferred.version}\n")
}
```

```yaml
# plugins/release/plugin.yaml — both tasks are build-graph contributors, so neither is in commands:
tasks:
  writeVersion:
    action: !io.example.release.tasks.writeVersion
      moduleRootDir: ${module.rootDir}
      outputDir: ${taskOutputDir}
      settings: ${pluginSettings}

  writeReleaseProperties:
    action: !io.example.release.tasks.writeReleaseProperties
      moduleRootDir: ${module.rootDir}
      outputDir: ${taskOutputDir}
      settings: ${pluginSettings}

generated:
  resources:
    - directory: ${tasks.writeVersion.action.outputDir}
    - directory: ${tasks.writeReleaseProperties.action.outputDir}
```

## 9. Release plugin on the root module — break the task loop

When `${module.rootDir}` is the project root (which contains `build/`), dependency inference treats every
build output as an input of any task taking `@Input moduleRootDir: Path`, giving
"Task dependency loop detected" on `./kotlin show modules` or `build`. Opt out on every such parameter:

```kotlin
@TaskAction
fun currentVersion(
    @Input(inferTaskDependency = false) moduleRootDir: Path,
    settings: Settings,
) { /* ... */ }
```

## 10. `.github/workflows/ci.yml`

No `setup-java`; the wrapper provisions its JDK. The upload path is the stable `build/libs/` from the
`package` plugin.

```yaml
name: CI

on:
  push:
    branches-ignore: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  build:
    runs-on: ubuntu-latest

    env:
      KOTLIN_CLI_NO_WELCOME_BANNER: "1"

    steps:
    - uses: actions/checkout@v6
      with:
        fetch-depth: 0  # the release plugin derives the version from git tags

    - name: Build with Kotlin Toolchain
      run: |
        ./kotlin build
        ./kotlin check
        ./kotlin do package

    - name: Upload build artifacts
      uses: actions/upload-artifact@v7
      with:
        name: build-artifacts
        path: build/libs/
```

## 11. `.github/workflows/release.yml` — the version-capture step

Full workflow: registry login → `checkout` with `fetch-depth: 0` → verify → tag → capture version → publish.
The only non-obvious part:

```yaml
      - name: Tag release
        run: ./kotlin do release

      - name: Resolve current release version
        id: tag_version
        run: |
          # Read the tag the release just created. Do NOT parse `./kotlin do currentVersion`
          # stdout: it is a decorated log line followed by a `<task> successful` banner.
          current_version=$(git describe --tags --exact-match HEAD | sed 's/^v//')
          echo "version=$current_version" >> $GITHUB_OUTPUT

      - name: Build and publish Docker image
        run: ./kotlin do jib
```

Dynamic image tags reach the plugin through an env var read inside the task action (no `-P`/`-D`). Document
the variable in the plugin's README.

## 12. `.github/dependabot.yml`

Group the new local-plugin runtime libraries so Dependabot consolidates PRs, and drop pre-existing groups
whose patterns no longer match the catalog.

```yaml
version: 2
updates:
  - package-ecosystem: "gradle"
    directory: "/"
    schedule:
      interval: "weekly"
      day: "monday"
    open-pull-requests-limit: 5
    groups:
      detekt:
        patterns: ["io.gitlab.arturbosch.detekt*", "com.github.marc0der*"]
      jib:
        patterns: ["com.google.cloud.tools*"]
      release-plugin:
        patterns: ["org.eclipse.jgit*", "org.bouncycastle*", "org.slf4j*"]

  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
      day: "monday"
```

## 13. `.gitignore`

Replace the Gradle-specific lines with:

```
# Kotlin Toolchain
build/
```

The Toolchain's other caches live outside the repo (`~/Library/Caches/JetBrains/Kotlin/`,
`~/.cache/JetBrains/Kotlin/` on Mac).
