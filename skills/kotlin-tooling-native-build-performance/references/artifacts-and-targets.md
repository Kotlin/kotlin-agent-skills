# Build the Right Artifact for the Feedback Loop

A release binary takes roughly an order of magnitude longer to build than a
debug binary, and umbrella tasks such as `build` and `assemble` compile the
same code several times. Map each feedback loop to one specific task.

## Task table

| Feedback loop | Correct task |
|---|---|
| Xcode builds and runs the app (direct integration) | `:shared:embedAndSignAppleFrameworkForXcode` |
| Gradle-only check of the Apple Silicon simulator framework | `:shared:linkDebugFrameworkIosSimulatorArm64` |
| CocoaPods integration | `:shared:linkPodDebugFrameworkIosSimulatorArm64` |
| Distribution or App Store validation | `assemble<Name>ReleaseXCFramework` — in CI, not in the local loop |
| Debug XCFramework genuinely required | `assemble<Name>DebugXCFramework` |

Per-target link tasks follow the pattern
`link<BuildType>Framework<Target>`; find the exact names with
`./gradlew :shared:tasks` or in the build log.

## Rules

- `embedAndSignAppleFrameworkForXcode` builds only the slice Xcode asked for
  and must run from an Xcode build phase, not standalone. Direct integration
  uses the documented run-script phase; keep its
  `OVERRIDE_KOTLIN_BUILD_IDE_SUPPORTED` guard so the IDE does not trigger a
  second Gradle invocation.
- Do not mix integration methods: a project either uses direct integration or
  the CocoaPods integration, and the local task must match the one in use.
- Do not replace CI release artifacts with debug artifacts. If CI release
  builds are slow, fix caching, the target matrix, and exports instead.

## Target matrix

`*XCFramework` tasks build every declared target. Remove a target only when
project policy confirms it is unused — the common case is dropping
`iosX64()` when the team no longer supports Intel-based simulators. State the
policy assumption in your report; if policy is unclear, ask instead of
deleting.

Docs:
https://kotlinlang.org/docs/multiplatform-ios-integration-overview.html,
https://kotlinlang.org/docs/multiplatform/multiplatform-direct-integration.html,
https://kotlinlang.org/docs/multiplatform/multiplatform-build-native-binaries.html
