---
name: kotlin-tooling-kotlin-toolchain-plugin-authoring
description: >
  Load when authoring, writing, or designing a Kotlin Toolchain local plugin to
  extend the declarative build with code generation, build-time processing,
  custom verification, or packaging that module.yaml cannot express, or when
  referencing @TaskAction, @Configurable, plugin.yaml, or jvm/amper-plugin. Skip
  for porting an existing Gradle plugin.
license: Apache-2.0
metadata:
  author: github:@singleton11
  version: "0.1.0"
---

# Kotlin Toolchain Plugin Authoring

Local plugins are the official escape hatch from declarative YAML: a `jvm/amper-plugin` module shipping
task actions, settings, and generated sources/resources alongside your project. Code patterns to adapt are
in [references/examples.md](references/examples.md).

## When to write a plugin

Write one when you need:

- A build-time step a library's workflow expects (code generation, schema compilation, resource
  transformation, version stamping).
- Custom verification wired into the build (pre-release checks, schema validation, contract tests).
- A build-time value published into the JAR classpath or downstream tasks — the closest analog to Gradle's
  `project.version`.
- A named CLI command for a repeated workflow (`./kotlin do release`).

Don't write one when `module.yaml` already covers it (dependencies, JDK provisioning, source layouts,
basic packaging), and never to reuse a Gradle plugin — the Kotlin Toolchain cannot consume them.

## Layout

```
repo-root/
├── kotlin, kotlin.bat            # wrappers (from `kotlin init`)
├── project.yaml                  # registers the plugin
├── plugins/<name>/
│   ├── module.yaml               # product: jvm/amper-plugin
│   ├── plugin.yaml               # tasks: + commands: + generated:
│   └── src/
│       ├── Settings.kt           # @Configurable interface
│       ├── tasks/                # one @TaskAction per file
│       │   ├── Foo.kt
│       │   └── FooSteps.kt       # internal shared helpers (not @TaskAction)
│       └── <domain logic>/
└── <consumer-module>/
    └── module.yaml               # plugins: { <name>: enabled: true, ... }
```

Keep at least one consumer module in the repo — it is the only way to exercise the plugin end-to-end, and
plugins cannot be published to any public registry yet.

## `project.yaml`

```yaml
modules:
  - consumer-app
  - plugins/<name>

plugins:
  - ./plugins/<name>
```

Without the top-level `plugins:` block the plugin id is unresolvable from any consumer.

## `module.yaml` — the plugin module

```yaml
product: jvm/amper-plugin          # marks the module as a plugin

dependencies:
  - <coordinate>:<version>
  - <coordinate>:<version>: runtime-only   # required only at runtime
  - <coordinate>:<version>: compile-only

pluginInfo:
  id: <plugin-id>                                  # what consumers write under `plugins:`
  settingsClass: <fully.qualified.Settings>        # the @Configurable interface

settings:
  jvm:
    jdk:
      version: 21
  kotlin:
    languageVersion: 2.1
```


## `@Configurable interface Settings`

Defaults go in interface property getters; nested blocks become nested `@Configurable` interfaces.

```kotlin
@Configurable
interface Settings {
    val someValue: String get() = "default"
    val checks: ChecksSettings
}

@Configurable
interface ChecksSettings {
    val strict: Boolean get() = true
}
```

Consumers override what they need in `module.yaml`; omitted values fall back to the getter default:

```yaml
plugins:
  <plugin-id>:
    enabled: true
    someValue: "override"
    checks:
      strict: false
```

## `@TaskAction`

Task actions are top-level `fun`s, called when the matching `plugin.yaml` entry executes.

```kotlin
@TaskAction
fun foo(
    @Input moduleRootDir: Path,
    @Output outputDir: Path,
    settings: Settings,
) {
    // body
}
```

- `@Input path: Path` — declared input; Kotlin Toolchain snapshots its contents for execution avoidance.
- `@Output path: Path` — declared output directory; Kotlin Toolchain creates it and passes the path in. Write
  to the exact `Path` you received, or downstream references won't find the result.
- `settings: Settings` (or any `@Configurable`) — typed configuration, wired in `plugin.yaml`.
- Plain `Path` / primitives — passed literally from `plugin.yaml`.
- `println(...)` is the output channel; Kotlin Toolchain captures stdout.

### Execution avoidance

A `@TaskAction` is skipped when its declared inputs are unchanged. Tasks whose real inputs are Git history,
the network, or environment variables cannot be fingerprinted, so opt out:

```kotlin
@TaskAction(executionAvoidance = ExecutionAvoidance.Disabled)
fun foo(@Output outputDir: Path, settings: Settings) { /* ... */ }
```

Tasks with no `@Output` are never cached and always re-run — correct for purely side-effecting tasks
(releases, deployments, pushes).

## `plugin.yaml`

```yaml
tasks:
  foo:
    action: !<fully.qualified.foo>
      moduleRootDir: ${module.rootDir}
      outputDir: ${taskOutputDir}
      settings: ${pluginSettings}

  bar:
    action: !<fully.qualified.bar>
      input: ${tasks.foo.action.outputDir}/result.txt
      settings: ${pluginSettings}

generated:
  resources:
    - directory: ${tasks.foo.action.outputDir}

commands:
  - foo
```

| Reference | Resolves to |
|---|---|
| `${module.rootDir}` | Directory containing the consumer's `module.yaml`. Pass as `@Input` to inspect the consumer's tree. |
| `${taskOutputDir}` | Toolchain-managed per-task output directory. Pass as `@Output`. |
| `${pluginSettings}` | The `@Configurable` object built from the consumer's `module.yaml`. |
| `${tasks.<task>.action.<param>}` | Another task's parameter — used in `generated.*` and to wire one task's `@Input` to another's `@Output`. |

### `generated.resources` / `generated.sources`

Both register a directory (usually a task's `@Output`) as a contribution to the consumer's build, and both
auto-wire the producing task to run first:

- `generated.resources` — added to the JAR classpath, reachable via `getResourceAsStream("/path/in/jar")`.
- `generated.sources` — added as a Kotlin source root and compiled with the consumer's `src/`.

### Tasks vs commands

Tasks are the implementation, addressed as `./kotlin task :<module>:<task>@<plugin-id>` — the docs advise
against relying on that mangled name. Commands are the public API: `./kotlin do <command-name>`, listed via
`./kotlin show commands` (`-m <module>` to scope).

- A task whose `@Output` feeds `generated.resources`/`generated.sources` is a build-graph contributor. Keep
  it out of `commands:`; it runs automatically and exposing it invites users to run it by hand.
- A task users invoke directly must be in `commands:`.

## File-based task communication

There is no shared mutable build state — no `project.version`, no extension property maps. Tasks talk
through matched paths:

1. The producer takes `@Output outputDir: Path` and writes files into it.
2. `plugin.yaml` points a consumer task's `@Input` at `${tasks.<producer>.action.outputDir}/<file>`.
3. The Toolchain infers the dependency from the path match — no `dependsOn` API needed.

The same `@Output` directory can serve build-time consumers (via `@Input`) and runtime consumers
(registered under `generated.resources`, read via `getResourceAsStream`) simultaneously.

## Runtime overrides via environment variables

There is no `-Pkey=value`. Read env vars inside the action for ephemeral overrides:

```kotlin
val forced = System.getenv("MYPLUGIN_FORCE_VALUE")?.takeIf { it.isNotBlank() }
val skipChecks = System.getenv("MYPLUGIN_SKIP_CHECKS")?.equals("true", ignoreCase = true) == true
```

Pass the env map in as a constructor parameter rather than calling `System.getenv()` deep in the call stack,
so logic stays unit-testable. Document every recognised variable in the plugin's README. Env vars are
ephemeral overrides, not a trust boundary — validate a value before using it in a file path or process
argument.

## Sharing logic across task actions

Tasks often share steps (verify → create → push). Don't compose an atomic user-facing task from a chain of
build-graph tasks: separate invocations re-open shared resources and open a window where another process
observes intermediate state.

## Limitations to design around

- Plugins are local-only; no public registry publishing yet.
- Plugins are module-level; there is no project-wide plugin. Every consumer module lists it under
  `plugins:`, and cross-module effects flow through files.
- No `${...}` interpolation in `module.yaml` (as of 0.11) — consumer settings are literal values.
- No `Project.afterEvaluate`, no lazy `Provider`/`Property` graph. Compute derived values in the action body.
- `-h`/`--help` does not list plugin commands; use `./kotlin show commands`.

## Validate against a consumer

1. Add a small consumer module (`demo-app/`, `sample/`) enabling the plugin with realistic settings.
2. Have its `main.kt` or a test read whatever the plugin publishes.
3. Put the exact commands and expected output in the plugin's README, so a fresh clone can paste and compare.

Plugin docs: <https://kotlin-toolchain.org/dev/user-guide/plugins/>
