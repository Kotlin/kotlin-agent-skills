# Caching and Gradle Configuration

Safe for every scenario; apply these before anything else.

## Update Kotlin

The latest Kotlin version is the first official recommendation for
Kotlin/Native compilation time — each release improves compiler performance.
Check `gradle/libs.versions.toml` or the plugin block and propose an upgrade
if the project is behind.

## Remove stale workarounds

Projects accumulate workarounds for long-fixed compiler issues. Look for:

- `kotlin.native.cacheKind=none` (also per-target variants such as
  `kotlin.native.cacheKind.iosSimulatorArm64=none`)
- `kotlin.native.disableCompilerDaemon=true`
- `disableNativeCache(...)` in the `binaries {}` DSL
- `org.gradle.daemon=false`

Each disables a default that exists for performance. Remove them unless a
comment or commit message ties them to a still-open issue — verify the issue
is still open before keeping the workaround, and re-test after removal.

## Enable Gradle caching

```properties
# gradle.properties
org.gradle.caching=true
org.gradle.configuration-cache=true
org.gradle.jvmargs=-Xmx3g -Dfile.encoding=UTF-8
```

- Trial the configuration cache with the user's real task before committing
  it. If Gradle reports configuration-cache problems, fix the blockers listed
  in the HTML report instead of abandoning the cache.
- The configuration cache implicitly enables parallel task execution, which
  can run several `link*` tasks at once and overload the machine (KT-70915).
  If that happens, bound it with `org.gradle.workers.max` in
  `gradle.properties` or `--max-workers` on the command line — do not turn
  the cache off for this reason alone.
- Delete `org.gradle.configureondemand=true`. Kotlin Multiplatform does not
  support Configuration on Demand, and it is not the same feature as the
  configuration cache.
- If compilation itself is memory-bound, give the Kotlin daemon its own heap
  with `kotlin.daemon.jvmargs=-Xmx3g` rather than only growing the Gradle
  daemon.
- For CI, a remote Gradle build cache extends `org.gradle.caching` across
  machines.

## Keep `~/.konan` warm in CI

Kotlin/Native stores its compiler distribution and caches in `$HOME/.konan`.
Ephemeral CI machines and containers that lose it pay the cold-start cost on
every build. On GitHub Actions:

```yaml
- uses: actions/cache@v4
  with:
    path: ~/.konan
    key: konan-${{ runner.os }}-${{ hashFiles('**/libs.versions.toml') }}
```

Use the `konan.data.dir` Gradle property only when the project intentionally
relocates that directory (for example, to a cacheable path on a CI runner).

Docs: https://kotlinlang.org/docs/native-improving-compilation-time.html and
https://kotlinlang.org/docs/gradle-compilation-and-caches.html
