---
name: kotlin-tooling-native-build-performance
description: >
  Diagnoses and fixes slow Kotlin/Native compilation and linking in Kotlin
  Multiplatform projects that target iOS. Use when the user reports slow iOS or
  shared-framework builds, long linkDebug*/linkRelease* or XCFramework tasks,
  cold CI builds that re-download the Kotlin/Native toolchain, disabled
  Kotlin/Native caches (kotlin.native.cacheKind=none), kapt or generated code
  on the native path, transitiveExport usage, or asks for a local-development
  versus CI build performance plan.
license: Apache-2.0
metadata:
  author: JetBrains
  version: "1.0.0"
---

# Kotlin/Native Build Performance

Turn "the iOS build is slow" into a measured diagnosis and a small set of safe
fixes. Two rules apply throughout:

1. Never trade away required release behavior. A faster local loop must not
   change what CI publishes.
2. Measure before and after with the same command and the same build state.
   An unmeasured fix is a guess.

## Step 0: Classify the Slow Scenario

Establish four facts before editing anything: **where** (local or CI),
**what** (debug feedback loop or release/distribution artifact), **state**
(first build, clean, warm, or no-op), and **phase** (which tasks dominate the
log). Then match the dominant symptom:

| Symptom in the build log | Likely cause | Read |
|---|---|---|
| `linkRelease*` or `*ReleaseXCFramework` tasks in a local development loop | Building distribution artifacts for development | [artifacts-and-targets](references/artifacts-and-targets.md) |
| Kotlin/Native compiler distribution downloaded on every CI run | `~/.konan` not preserved between runs | [caching-and-gradle](references/caching-and-gradle.md) |
| Long pause before the first task starts | Configuration phase, no configuration cache | [caching-and-gradle](references/caching-and-gradle.md) |
| All iOS targets build when only one simulator is needed | Broad task (`build`, `assemble`, `assemble*XCFramework`) or unused targets | [artifacts-and-targets](references/artifacts-and-targets.md) |
| `kapt*` or `ksp*` tasks ahead of `compileKotlinIos*` | Generated-code work on the native path | [exports-and-generated-code](references/exports-and-generated-code.md) |
| Small source edit recompiles and relinks everything | Compiler caches disabled, or missing incrementality | [caching-and-gradle](references/caching-and-gradle.md), [experimental](references/experimental.md) |
| Machine overloaded while several `link*` tasks run at once | Parallel native linking | [caching-and-gradle](references/caching-and-gradle.md), worker-limit caveat |

## Step 1: Audit and Measure

1. Run the static audit from the project root:

   ```bash
   scripts/audit-native-build.sh /path/to/project
   ```

   It is read-only and prints `file:line` findings (disabled caches, broad
   local tasks, `transitiveExport`, kapt on the native path, missing CI
   `.konan` cache), each pointing at the reference file with the fix.
   Findings are leads, not verdicts — confirm each against project policy.
2. Find the command the user actually waits for: a script, a CI step, or the
   Gradle invocation inside an Xcode build phase. Optimize that command, not
   a task you picked yourself.
3. Run it twice when practical. The first build downloads Kotlin/Native
   components and fills caches; only the second and later runs are
   representative. Attribute time per task before blaming the compiler:

   ```properties
   kotlin.build.report.output=file   # writes build/reports/kotlin-build/
   ```

   Gradle's `--scan` or `--profile` work too.
4. If you cannot run the build (no macOS host, no Xcode), analyze logs, build
   scans, or checked-in metrics instead — and state explicitly that the
   conclusion is static.

## Step 2: Fix in Safe Order

Apply fixes one at a time, re-measuring as you go:

1. **Restore healthy defaults** — remove cache/daemon workarounds, enable
   Gradle build and configuration caches, keep `~/.konan` warm in CI, update
   Kotlin: [references/caching-and-gradle.md](references/caching-and-gradle.md)
2. **Build only what the feedback loop needs** — one specific task per loop,
   correct integration method, justified target matrix:
   [references/artifacts-and-targets.md](references/artifacts-and-targets.md)
3. **Cut export and generated-code cost** — drop `transitiveExport`, narrow
   `export(...)`, move kapt work to scoped KSP:
   [references/exports-and-generated-code.md](references/exports-and-generated-code.md)
4. **Experimental switches last, with the user's agreement**:
   [references/experimental.md](references/experimental.md)

## Worked Example

A developer on an Apple Silicon Mac complains that "every shared-module
change costs 12 minutes". Their loop runs `./gradlew :shared:assembleXCFramework`.
A build scan of the second (warm) run shows:

```
:shared:linkReleaseFrameworkIosArm64             348s
:shared:linkReleaseFrameworkIosX64               341s
:shared:compileKotlinIosX64                       96s
:shared:linkDebugFrameworkIosSimulatorArm64       41s
:shared:compileKotlinIosSimulatorArm64            38s
configuration phase                               64s
```

Reasoning chain:

- The loop is **local + debug + warm**, but ~690s goes to `linkRelease*` —
  release linking is an order of magnitude slower than debug and only CI
  needs it. Replace the local command with
  `:shared:linkDebugFrameworkIosSimulatorArm64` (or the Xcode embed task if
  Xcode drives the build). *(artifacts-and-targets)*
- All `iosX64` work serves Intel simulators; ask whether the team still
  supports them before removing the target. *(artifacts-and-targets)*
- 64s of configuration on every run disappears behind
  `org.gradle.configuration-cache=true` once trialed. *(caching-and-gradle)*
- Expected loop after the change: ~40s compile + ~40s link on warm builds —
  confirm by re-running the new command twice and comparing.
- CI keeps `assembleXCFramework` untouched; note that explicitly in the
  report.

## Verify

- [ ] Re-run the exact baseline command; compare warm build against warm
      build, not warm against cold.
- [ ] Second run with the configuration cache reports it is being reused.
- [ ] The local development log no longer contains `linkRelease*`,
      `*ReleaseXCFramework`, or removed generator tasks.
- [ ] CI still produces every required release artifact, unchanged.
- [ ] Tests pass and the app still runs from Xcode.
- [ ] `scripts/audit-native-build.sh` reports no findings you have not
      consciously accepted and documented.

## Report Your Changes

Close with a short performance note:

- The slow scenario (local/CI, debug/release, cold/warm) and the measured
  evidence — or a statement that the analysis was static.
- Each change, and why it is safe for release behavior.
- The before/after commands the user can run to confirm the win.
- Remaining tradeoffs: experimental flags enabled, targets removed under a
  policy assumption, worker limits, or generated-code work deferred.
- Links to the relevant official documentation below.

## Official Documentation

| Topic | Link |
|---|---|
| Improving Kotlin/Native compilation time | https://kotlinlang.org/docs/native-improving-compilation-time.html |
| Kotlin Gradle plugin compilation and caches | https://kotlinlang.org/docs/gradle-compilation-and-caches.html |
| iOS integration methods | https://kotlinlang.org/docs/multiplatform-ios-integration-overview.html |
| Direct integration with Xcode | https://kotlinlang.org/docs/multiplatform/multiplatform-direct-integration.html |
| Building final native binaries and XCFrameworks | https://kotlinlang.org/docs/multiplatform/multiplatform-build-native-binaries.html |
| Kotlin/Native binary options | https://kotlinlang.org/docs/native-binary-options.html |
| KSP with Kotlin Multiplatform | https://kotlinlang.org/docs/ksp-multiplatform.html |

## Testing

A/B evaluated with the
[skills-ab-eval cookbook suite](https://github.com/JetBrains/skills-ab-eval-cookbook-kmp)
(`kotlin-tooling-native-build-performance`: a synthetic audit fixture and a
KotlinProject template copy with seeded regressions). See the suite's
`EVALUATION.md` for current numbers.
