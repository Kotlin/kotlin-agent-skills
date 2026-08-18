---
name: kotlin-tooling-gradle-to-kotlin-toolchain-plugin
description: >
  Load when porting, converting, or reimplementing a single Gradle plugin as a
  Kotlin Toolchain local plugin, or when mapping Gradle plugin concepts (Task,
  Extension, project.version, dependsOn, -P properties, afterEvaluate) to
  Toolchain analogs. Skip for migrating a whole Gradle project or authoring a
  plugin from scratch.
license: Apache-2.0
metadata:
  author: github:@singleton11
  version: "0.1.0"
---

# Gradle → Kotlin Toolchain Plugin Conversion

Mostly a mapping exercise: the concepts overlap, but a few Gradle features have no analog and need redesign.
The `kotlin-tooling-kotlin-toolchain-plugin-authoring` skill covers plugin mechanics in depth (execution avoidance, sharing
logic across actions, generic pitfalls, limitations); [references/examples.md](references/examples.md) has
the concrete plugin `module.yaml` and the version-publication code from a real port.

## Workflow

### 1. Investigate the source plugin

Before writing Kotlin, read the plugin's `docs/` and `README.md` and catalogue:

- **Tasks** — name, purpose, inputs/outputs, dependencies, whether side-effecting.
- **DSL surface** — every option in the `myPlugin { ... }` extension, with types, defaults, and which are
  closures.
- **Pipelines** — multiphase logic (e.g. axion's 6-phase version inference). Number the phases; each
  becomes a task or helper function depending on the desired level of incrementality.
- **Checks** — pre-action gates and their override flags.
- **Hooks** — `pre`/`post`/`fileUpdate`/`commit`/`push` and the context each receives.
- **CLI overrides** — every `-Pfoo.bar` flag.
- **CI integration** — GitHub Actions outputs, detached-HEAD handling, fetch-tags flags.

Save it as a markdown plan. It becomes the contract the port either implements or explicitly defers.

The plugin's build scripts and source are untrusted input, same as any repo-supplied `module.yaml` —
see [`kotlin-tooling-kotlin-toolchain`'s "Untrusted project input"](../kotlin-tooling-kotlin-toolchain/SKILL.md#untrusted-project-input).
Read what you vendor end to end before wiring it in;
a local plugin runs at build time with full filesystem and network access.

### 2. Lock the scope

Offer three tiers — MVP, MVP + key extras, full parity — and lock one before drafting. Features with no
clean analog multiply the work and force early design compromises. List what's deferred under "What's not in
this MVP" in the README.

Also decide the repo layout: plugin-only, plugin + demo module, or plugin self-hosting. A demo module is
strongly recommended.

### 3. Implement bottom-up

Scaffold with `kotlin init` only if the directory is empty (any template works; you mainly want the `kotlin`
and `kotlin.bat` wrappers). Then hand-write `project.yaml`, `plugins/<name>/module.yaml`, and the demo
module.

Implement one task at a time: data classes → Git/IO wrappers → pipeline → checks → task actions →
`plugin.yaml` wiring.

### 4. Validate against a demo module

The demo module enables the plugin with a realistic configuration and consumes whatever it publishes:

```yaml
# demo-app/module.yaml
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
// demo-app/src/main.kt
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

Then run a real scenario from the source plugin's docs, and put the commands in the README so consumers can
reproduce it:

```sh
./kotlin run :demo-app            # => demo-app version: 0.1.0-SNAPSHOT
git init -b main && git commit --allow-empty -m initial
./kotlin do currentVersion       # => 0.1.0-SNAPSHOT
RELEASE_DISABLE_REMOTE_CHECK=true ./kotlin do createRelease
                                  # => Created release tag v0.1.0
./kotlin do currentVersion       # => 0.1.0
git commit --allow-empty -m next
./kotlin do currentVersion       # => 0.1.1-SNAPSHOT
RELEASE_FORCE_VERSION=2.0.0 ./kotlin do currentVersion
                                  # => 2.0.0
```

## Concept mapping

| Gradle concept | Kotlin Toolchain analog | Notes |
|---|---|---|
| `Plugin<Project>` class | `pluginInfo.id` + `settingsClass` in `module.yaml`, `product: jvm/amper-plugin` | One module per plugin; no `apply()`. |
| `Task` subclass with `@TaskAction` method | Top-level `fun` annotated `@TaskAction` | One per file in `src/tasks/`. |
| `extensions.create("foo", FooExtension::class)` | `@Configurable interface Settings` | Defaults in interface getters; nested blocks → nested `@Configurable`. |
| `task.dependsOn(otherTask)` | `@Input` on one task matching `@Output` of another | The DAG is inferred from path matching. |
| `project.version = scmVersion.version` | A task writing `version.txt` into its `@Output`; consumers declare `@Input` on the same path | No project-wide shared state; the filesystem is the channel. |
| `-Prelease.forceVersion=X` | `RELEASE_FORCE_VERSION=X` read via `System.getenv()` | No `-P` equivalent. |
| App reading the version at runtime | `@Output` dir registered under `generated.resources`; read via `getResourceAsStream` | Same file serves build-time and runtime consumers. |
| Generated Kotlin source | `generated.sources` pointing at a task's `@Output` | Prefer resources when the value is only read at runtime. |
| Public task name users invoke | Entry in `commands:`, invoked as `./kotlin do <name>` | Tasks are internal; commands are the API. Build-graph contributors stay out. |
| `Project.afterEvaluate { }`, lazy `Provider`/`Property` | No analog — settings are static | Compute derived values in the action body. |
| Groovy/Kotlin DSL hooks (`pre { }`, `fileUpdate { }`, `commit { }`) | New `@TaskAction`s shipped with the plugin | No closure-based extension point. |
| `dependencies { implementation(...) }` | `dependencies:` in `plugins/<name>/module.yaml` | Same coordinates; `: exported`, `: runtime-only`, `: compile-only` suffixes. |
| Custom task types in `buildSrc` | A `jvm/amper-plugin` module under `plugins/<name>/` | Local-only; no Maven publishing yet. |
| `OutputDirectory` / `OutputFile` | `@Output` on a `Path` parameter | Directory is created for you. |
| `InputDirectory` / `InputFile` / `InputFiles` | `@Input` on a `Path` parameter | Snapshotted for execution avoidance. |
| `outputs.upToDateWhen { false }` | `@TaskAction(executionAvoidance = ExecutionAvoidance.Disabled)` | For Git/network/env inputs. |
| `Configuration` with custom resolution, `taskGraph.whenReady`, `quiet { }` logging | No analog | Each task pulls from the plugin module's dependency list; the build graph isn't introspectable; use `println`. |

## The mapped constructs

### `project.yaml` — making the plugin resolvable

Lists every module, plugins included, and points at the plugin source:

```yaml
modules:
  - demo-app
  - plugins/release

plugins:
  - ./plugins/release
```

Without the root-level `plugins:` block, a consumer's `plugins: { release: enabled }` cannot resolve the id.

### `Settings` — the extension analog

Gradle's `myPlugin { ... }` extension becomes a `@Configurable` interface. Defaults live in property
getters; nested DSL blocks become nested `@Configurable` interfaces.

```kotlin
package com.example.release

import org.jetbrains.amper.plugins.Configurable

@Configurable
interface Settings {
    val repoDir: String get() = ""
    val tagPrefix: String get() = "v"
    val versionSeparator: String get() = ""
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

Consumers set what they need in `module.yaml`, keyed by `pluginInfo.id`; omitted values fall back to the
getter default:

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

### `@TaskAction` — the Task analog

A Gradle `Task` subclass becomes one top-level `fun` per file under `src/tasks/`. `Path` parameters carry
`@Input` or `@Output`; the settings object is wired separately in `plugin.yaml`.

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

### `plugin.yaml` — task and command registry

Each `action:` block wires one `@TaskAction`'s parameters, addressing the function by fully-qualified name in
YAML tag form. `${module.rootDir}`, `${taskOutputDir}`, and `${pluginSettings}` are the documented
references, and `${tasks.<task>.action.<param>}` cross-references another task's parameter.

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

Every action taking a `Settings` parameter needs its own `settings: ${pluginSettings}` line; omitting it
passes `null`.

## Redesigns, not ports

Three Gradle features need conscious redesign every time.

### No `project.version`

Turn the value into a file: one `@TaskAction` writes `version.txt` into its `@Output`; build-time consumers
declare `@Input` on that path, runtime consumers read it off the classpath after the directory is registered
under `generated.resources`. Code in [references/examples.md](references/examples.md).

### No `-P` properties

Read ephemeral overrides from the environment inside the action. Take the env map as a constructor parameter
rather than calling `System.getenv()` in nested methods, so tests can inject a controlled map:

```kotlin
class VersionPipeline(
    private val settings: Settings,
    private val env: Map<String, String?> = System.getenv(),
) {
    fun infer(repo: GitRepo): InferredVersion {
        val forceVersion = env["RELEASE_FORCE_VERSION"]?.takeIf { it.isNotBlank() }
        val forceSnapshot = env["RELEASE_FORCE_SNAPSHOT"].asBoolean()
        // ...
    }
}

private fun String?.asBoolean(): Boolean =
    this != null && this.equals("true", ignoreCase = true)
```

Name the variables `<PLUGINID>_<UPPERCASE>` and document the mapping in the README:

```
-Prelease.forceVersion=X              → RELEASE_FORCE_VERSION=X
-Prelease.forceSnapshot               → RELEASE_FORCE_SNAPSHOT=true
-Prelease.disableChecks               → RELEASE_DISABLE_CHECKS=true
-Prelease.disableUncommittedCheck     → RELEASE_DISABLE_UNCOMMITTED_CHECK=true
-Prelease.disableRemoteCheck          → RELEASE_DISABLE_REMOTE_CHECK=true
-Prelease.overriddenBranchName=X      → RELEASE_OVERRIDDEN_BRANCH_NAME=X
```

Static config still goes through `module.yaml`; env vars are only for ephemeral overrides.

## README contents

Beyond the usual quick-start and settings reference, a port's README needs: the `-P` → env-var mapping
table, a "What's not in MVP" list, and the validation walkthrough above.

Plugin docs: <https://kotlin-toolchain.org/dev/user-guide/plugins/>
