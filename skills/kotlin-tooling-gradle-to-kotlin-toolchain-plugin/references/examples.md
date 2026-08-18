# Conversion patterns — concrete code

Lifted from a real conversion: `allegro/axion-release-plugin` ported to a Kotlin Toolchain local release
plugin. Adapt names, types, and imports. The constructs themselves (`project.yaml`, `Settings`,
`@TaskAction`, `plugin.yaml`) are in the skill body.

## 1. `plugins/<name>/module.yaml`

Declare the Maven coordinates of every library the plugin uses, including transitive optionals that only fire
at runtime. `pluginInfo.id` is what tasks are addressed by (`...@release`) and what consumers key their
`plugins:` block on; `pluginInfo.settingsClass` is the fully-qualified `@Configurable` interface.

```yaml
product: jvm/amper-plugin

dependencies:
  - org.eclipse.jgit:org.eclipse.jgit:7.0.0.202409031743-r
  - org.eclipse.jgit:org.eclipse.jgit.ssh.apache:7.0.0.202409031743-r
  # MINA SSHD (pulled in by jgit.ssh.apache) declares BouncyCastle as optional
  # at compile time but builds its random factory from it at runtime. Pin to
  # the version contemporary with MINA SSHD 2.13.x.
  - org.bouncycastle:bcprov-jdk18on:1.78.1: runtime-only
  - org.bouncycastle:bcpkix-jdk18on:1.78.1: runtime-only
  - org.slf4j:slf4j-nop:2.0.13

pluginInfo:
  id: release
  settingsClass: com.example.release.Settings

settings:
  jvm:
    jdk:
      version: 21
  kotlin:
    languageVersion: 2.1
```

## 2. File-based publication — the `project.version` analog

The Gradle idiom `version = scmVersion.version` shares one value across the whole build. Replace it with a
`@TaskAction` that writes a file. `ExecutionAvoidance.Disabled` is required because the real input (Git
history, branch name, working-tree state) cannot be fingerprinted.

```kotlin
package com.example.release.tasks

import com.example.release.Settings
import com.example.release.git.GitRepo
import com.example.release.version.VersionPipeline
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

That one `@Output` directory feeds two consumption paths.

**Build-time.** Any other task — in this plugin, another plugin, or user code — declares `@Input` on the same
path, and the dependency is inferred from the match:

```kotlin
@TaskAction
fun packageWithVersion(
    @Input versionFile: Path,
    // ...
) {
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

**Runtime.** The directory is registered under `generated.resources`, so the file lands on the JAR classpath:

```kotlin
fun version(): String? =
    object {}.javaClass.getResourceAsStream("/META-INF/release/version.txt")
        ?.bufferedReader()?.use { it.readText().trim() }
```

One publication point, two consumption channels, no Toolchain-side shared state.
