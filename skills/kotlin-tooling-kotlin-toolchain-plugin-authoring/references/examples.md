# Plugin authoring patterns

Snippets to adapt — rename packages and types to your domain. The running example is a release /
version-stamping plugin, because it exercises every mechanism (settings, task actions, `@Input`/`@Output`,
generated resources, env-var overrides) in one place.

## 1. `project.yaml`

```yaml
modules:
  - <consumer-module>
  - plugins/<name>

plugins:
  - ./plugins/<name>
```

## 2. `plugins/<name>/module.yaml`

```yaml
product: jvm/amper-plugin

dependencies:
  - <coordinate>:<version>
  - <coordinate>:<version>: runtime-only

pluginInfo:
  id: <plugin-id>
  settingsClass: com.example.<name>.Settings

settings:
  jvm:
    jdk:
      version: 21
  kotlin:
    languageVersion: 2.1
```

## 3. `@Configurable interface Settings`

```kotlin
package com.example.release

import org.jetbrains.amper.plugins.Configurable

@Configurable
interface Settings {
    val tagPrefix: String get() = "v"
    val initialVersion: String get() = "0.1.0"
    val ignoreUncommittedChanges: Boolean get() = false
    val releaseBranchPattern: String get() = "main|master"
    val checks: ChecksSettings
}

@Configurable
interface ChecksSettings {
    val uncommittedChanges: Boolean get() = true
    val aheadOfRemote: Boolean get() = true
    val snapshotDependencies: Boolean get() = true
}
```

Consumer `module.yaml`:

```yaml
plugins:
  release:
    enabled: true
    tagPrefix: "v"
    initialVersion: "0.1.0"
    ignoreUncommittedChanges: false
    checks:
      aheadOfRemote: true
```

## 4. `@TaskAction` — one per file under `src/tasks/`

```kotlin
package com.example.release.tasks

import com.example.release.Settings
import com.example.release.git.GitRepo
import com.example.release.version.VersionPipeline
import org.jetbrains.amper.plugins.Input
import org.jetbrains.amper.plugins.TaskAction
import java.nio.file.Path

@TaskAction
fun currentVersion(
    @Input moduleRootDir: Path,
    settings: Settings,
) {
    val pipeline = VersionPipeline(settings)
    GitRepo.open(moduleRootDir, settings.repoDir).use { repo ->
        println(pipeline.infer(repo).version)
    }
}
```

## 5. File-based publication — the `project.version` analog

One task writes the value into its `@Output`; everything else reads it from there. Execution avoidance is
disabled because the real input is Git state.

```kotlin
package com.example.release.tasks

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
fun writeVersion(
    @Input moduleRootDir: Path,
    @Output outputDir: Path,
    settings: Settings,
) {
    val pipeline = VersionPipeline(settings)
    val inferred = GitRepo.open(moduleRootDir, settings.repoDir).use { pipeline.infer(it) }

    outputDir.deleteRecursively()
    val versionFile = outputDir / "META-INF" / "release" / "version.txt"
    versionFile.createParentDirectories()
    versionFile.writeText(inferred.version + "\n")
}
```

Build-time consumer — declare `@Input` on a matching path and the dependency is inferred:

```kotlin
@TaskAction
fun packageWithVersion(@Input versionFile: Path) {
    val version = versionFile.readText().trim()
    // ...
}
```

```yaml
tasks:
  packageWithVersion:
    action: !com.example.packageWithVersion
      versionFile: ${tasks.writeVersion.action.outputDir}/META-INF/release/version.txt
```

Runtime consumer — the directory is registered under `generated.resources` (§6), so the file is on the
classpath:

```kotlin
fun version(): String? =
    object {}.javaClass.getResourceAsStream("/META-INF/release/version.txt")
        ?.bufferedReader()?.use { it.readText().trim() }
```

## 6. `plugin.yaml`

```yaml
tasks:
  currentVersion:
    action: !com.example.release.tasks.currentVersion
      moduleRootDir: ${module.rootDir}
      settings: ${pluginSettings}

  writeVersion:
    action: !com.example.release.tasks.writeVersion
      moduleRootDir: ${module.rootDir}
      outputDir: ${taskOutputDir}
      settings: ${pluginSettings}

  release:
    action: !com.example.release.tasks.release
      moduleRootDir: ${module.rootDir}
      settings: ${pluginSettings}

generated:
  resources:
    - directory: ${tasks.writeVersion.action.outputDir}

# `writeVersion` stays out of commands: its @Output feeds generated.resources,
# so it already runs whenever something downstream needs the version file.
commands:
  - currentVersion
  - release
```

`!com.example.release.tasks.currentVersion` is the YAML tag form addressing a `@TaskAction` by
fully-qualified name.

## 7. Environment-variable overrides

Take the env map as a constructor parameter so tests can pass a controlled one.

```kotlin
class VersionPipeline(
    private val settings: Settings,
    private val env: Map<String, String?> = System.getenv(),
) {
    fun infer(repo: GitRepo): InferredVersion {
        val forced = env["RELEASE_FORCE_VERSION"]?.takeIf { it.isNotBlank() }
        val forceSnapshot = env["RELEASE_FORCE_SNAPSHOT"].asBoolean()
        // ...
    }
}

private fun String?.asBoolean(): Boolean =
    this != null && this.equals("true", ignoreCase = true)
```

## 8. Consumer module as validation harness

```yaml
# consumer-app/module.yaml
product: jvm/app

plugins:
  release:
    enabled: true
    tagPrefix: "v"
    initialVersion: "0.1.0"
    releaseBranchPattern: "main|master"

settings:
  jvm:
    mainClass: com.example.demo.MainKt
    jdk:
      version: 21
  kotlin:
    languageVersion: 2.1
```

```kotlin
// consumer-app/src/main.kt
package com.example.demo

private const val VERSION_RESOURCE = "/META-INF/release/version.txt"

fun main() {
    val version = readVersionFromClasspath() ?: "(version unavailable)"
    println("demo-app version: $version")
}

private fun readVersionFromClasspath(): String? =
    object {}.javaClass.getResourceAsStream(VERSION_RESOURCE)
        ?.bufferedReader()
        ?.use { it.readText().trim() }
        ?.takeIf { it.isNotEmpty() }
```

```sh
./kotlin run :consumer-app
./kotlin do <command-name>
./kotlin show commands
```
