# Evaluation

The skill is evaluated by having an agent migrate real Kotlin Multiplatform projects end to end and then
verifying the result independently: a clean Xcode build, a Maestro run of the app on a simulator, the non-iOS
Kotlin compiles, and a review of the build-file diff. The machine-checkable expectations are in
[`evals.json`](evals.json). The target model is the cheapest one that can carry the skill: Claude Haiku.

## Tested projects

| Project | Pre-migration state | What it exercises |
|---|---|---|
| [PeopleInSpace](https://github.com/joreilly/PeopleInSpace) | [`3a10b12`](https://github.com/joreilly/PeopleInSpace/tree/3a10b125dcd0e62335e70e64b2204ccd4d356079) (upstream's own Swift Export migration was reverted for the runs) | SKIE (incl. `enableSwiftUIObservingPreview`), Koin + Koin compiler plugin (no Kotlin 2.5-compatible release → the permission-gated Koin DSL rewrite), SQLDelight (`-lsqlite3`), kotlin-native-nuget (transitive KSP 2.3.10 → forced KSP), library `api` deps incl. a custom `nonWindowsMain` source set (→ `:ios-export` umbrella), shared module named `:common`, a macOS Xcode target Kotlin doesn't build (out of scope), `multiplatform-swiftpackage` publishing consumed by an in-repo Swift package (packaging decision), Android/JVM/wasm/mingw targets that must stay untouched |
| [WordMasterKMP](https://github.com/joreilly/WordMasterKMP) | [`cc63598`](https://github.com/joreilly/WordMasterKMP/tree/cc63598c87c019a5fd7a62fef4acc6d098a97cc5) (upstream's Swift Export migration reverted for the runs) | KMP-NativeCoroutines in its Swift Export compatibility mode (Gradle plugin + KSP + Swift package), direct export from `:shared`, iOS 15 deployment target, Kotlin enums inside collections (KT-90088 workaround), public `ArrayList` types |

Script fixtures (no end-to-end run): a WordMasterKMP copy on the deprecated `swiftExport { }` DSL, and one with
the framework configured in a `build-logic` convention plugin under a path with a space. `preflight.sh`,
`scan-objc-export-usages.sh` and `verify.sh --pbxproj-only` are checked against them after script changes.

## Method

- Each run starts from a fresh git worktree of the pre-migration state; one simulator per concurrent run.
- Runs are non-interactive, so the prompt answers the Phase 0 decisions up front (see `evals.json`); a variant
  without the answers must stop after Phase 0 and list every decision.
- The run is then verified by someone other than the agent: `scripts/verify.sh` (clean build with fresh derived
  data, Swift Export task ran, no ObjC-export leftovers, per-configuration Xcode settings, no deprecated DSL),
  a Maestro flow over every Kotlin-backed screen with the screenshots checked (WordMasterKMP: board and keyboard
  colours checked against the answer the app prints), the JVM/wasm/desktop/server compiles, and a diff review
  (non-iOS plugins and targets untouched, no plugin removed without approval).
- Every skill change is re-run on both projects; the agent's trace is read for steps where it deviated from or
  was unsure about the skill, which drives the next change.

## Latest results (2026-11-27)

Claude Code 2.1.332, model `claude-haiku-5-5`, Kotlin 2.5.0-RC2, Xcode 27, iOS 27 simulator.

| Skill state | Project | Result | Tool calls | Wall time |
|---|---|---|---:|---:|
| final | PeopleInSpace | pass (all assertions) | 78 | 8.5 min |
| final | WordMasterKMP | pass (all assertions, colours checked against the answer) | 54 | 6 min |
| previous iteration | PeopleInSpace | pass | 71 | 11 min |
| previous iteration | WordMasterKMP | pass | 78 | 9.5 min |

Over the development of the skill there were 13 Haiku runs on PeopleInSpace and 6 on WordMasterKMP; every
failure or detour found in a trace became a skill change (e.g. a stop-and-ask rule for plugin rewrites, the
umbrella module default, the KMP-NativeCoroutines compatibility mode, the up-front KT-90088 check). The
no-decisions variant was verified to stop after Phase 0 with the Koin plugin question instead of rewriting.

## With vs. without the skill (2026-11-27)

One pair on PeopleInSpace (eval 1 in `evals.json`), `claude-haiku-5-5`, identical prompt,
each arm in a fresh single-commit copy of the baseline (no git history, so no upstream migration to copy from);
only the with-skill arm got the skill. Both results were verified independently with the same checks.

| | Without skill | With skill |
|---|---|---|
| Outcome | **fail**: stopped with a WIP commit, iOS app doesn't build | **pass**: all `evals.json` assertions |
| `verify.sh` | FAIL (5 checks: build exit 65, Swift Export output missing, `xcode-frameworks` / `-framework common` left in the app target, sandboxing not set) | PASS |
| Swift Export build | fails in the generated bridges: kotlinx-coroutines `groupByTo` mismatch and `KotlinStdlib` `LazyThreadSafetyMode` (both libraries exported in full from `:common`); the agent hid SQLDelight, then gave up | builds; `:ios-export` umbrella, nothing hidden |
| Swift call sites | not touched (SKIE `onEnum(of:)` / `Observing` still in place) | rewritten (`sealedType()`, namespaces, `Observing` over `asAsyncSequence()`, `import KotlinRuntime`) |
| App on simulator (Maestro) | not runnable | people list, person detail, live ISS position |
| Scope | also switched the macOS target's Run Script to `:common:embedSwiftExportForXcode` (Kotlin builds no macOS target) | macOS target left untouched and reported |
| Toolchain fixes (KSP force, Koin DSL) | found on its own | from the skill |
| Requests / tool calls / wall time | 77 / 79 / 9.5 min | 67 / 68 / 7.7 min |
| Cost (API list price) | $0.73 | $0.60 |

Without the skill Haiku handled the toolchain part (it found the KSP and Koin fixes by itself) but not the
Swift Export part: it exported straight from the shared module, so the full export of its library `api`
dependencies broke the generated code, and it had no strategy past that. n = 1 per arm; more pairs, and
pairs on the other eval projects, would make this a measurement rather than an example.

Approximate cost of one run at Claude API list prices: $0.35–0.75 on Haiku 5.5 (most turns run above the
100K-token price step).

Not verified: Android builds (no Android SDK on the eval machine), Release/device/archive builds.

## Known gaps

- **CocoaPods** projects are sent to the `kotlin-tooling-cocoapods-spm-migration` skill first (it ends on the
  direct integration); the chained path (CocoaPods → SwiftPM import → Swift Export) is not evaluated end to end.
- **CI workflows** that build the iOS app or call `embedAndSignAppleFrameworkForXcode` / `assembleXCFramework` /
  packaging tasks are not updated.
- **Release, device and archive builds** are never verified: `verify.sh` builds Debug for the simulator (it
  checks the Release *settings* in `project.pbxproj`).
- **App extensions and widgets** are migrated like the app and checked when passed in `--targets`, but not run.
  **Test targets** that link Kotlin are not handled.
- **Run Scripts that call a wrapper script** instead of `./gradlew` are not detected as Gradle phases.
- **xcconfig-only settings** are reported as "check by hand", not parsed.
- **Compose Multiplatform resources** on iOS are not checked after the switch.
- **Several Swift-facing Kotlin modules**: preflight analyses one `<SHARED_MODULE>`; others are only listed.
- **The deprecated `swiftExport { }` DSL** and **framework config in convention plugins** are detected and
  handled, but verified on fixtures only, not by an end-to-end run.

## Deviations from the official Kotlin docs

Verified against code generated by Kotlin 2.5.0-RC2 and the Kotlin Gradle plugin 2.5.0 sources; to report
upstream (kotlin-web-site / kotl.in/issue).

1. **Open/abstract classes are supported.** The docs say only final classes are exported; in 2.5 `open` and
   `abstract` classes export as Swift `open class`, subclassable in Swift.
2. **`KotlinRuntime` is not re-exported**: the generated `<Module>.swift` imports it without `@_exported`, so
   Swift files that name `KotlinBase` need `import KotlinRuntime`.
3. **Direct `api` dependencies are exported in full**, and for common libraries (coroutines, SQLDelight, Koin,
   lifecycle, serialization) that fails to build or is very slow; the skill defaults to a thin umbrella module.
4. **KMP-NativeCoroutines is kept in its Swift Export compatibility mode** (per KMP-NativeCoroutines'
   `SWIFT_EXPORT.md`) instead of being removed as the draft migration guide says: a much smaller diff; removal
   is an optional later cleanup.
5. **Worker heap property**: the draft migration guide names `kotlin.swift-export.jvmArgs`, which doesn't exist;
   KGP 2.5.0 reads `kotlin.native.swiftExportWorkerJvmArgs` (default `-Xmx1g`).

## Sources

Kotlin docs: [Swift export overview](https://kotlinlang.org/docs/native-swift-export.html) and the draft setup
and migration-guide pages in [kotlin-web-site#5954](https://github.com/JetBrains/kotlin-web-site/pull/5954);
the Kotlin 2.5.0 sources (Kotlin Gradle plugin Swift Export DSL, diagnostics, tests);
[KMP-NativeCoroutines `SWIFT_EXPORT.md`](https://github.com/rickclephas/KMP-NativeCoroutines/blob/master/SWIFT_EXPORT.md);
[swift-export-sample](https://github.com/Kotlin/swift-export-sample); kotlin-swift-interopedia;
GuilhE/SwiftExport-Playground and GuilhE/Magic.
