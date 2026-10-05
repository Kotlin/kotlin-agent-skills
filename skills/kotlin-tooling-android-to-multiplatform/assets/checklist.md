# Android → KMP Migration Checklist

## Pre-Migration

- [ ] All shared module code is Kotlin (no Java files)
- [ ] No `java.*` / `android.*` APIs in code intended for `commonMain` (or replacements identified)
- [ ] Dependency audit done — Android-only deps have KMP alternatives or migration plan
- [ ] UI is Jetpack Compose (if sharing UI)
- [ ] Module boundaries are clean; migration order determined (leaf modules first)
- [ ] AGP 9.0+ recommended (use `kotlin-tooling-agp9-migration` skill if needed)

---

## Per-Module Migration

- [ ] Plugin switched to `android.multiplatform.library` (AGP 9) or `kotlin.multiplatform` + `android.library`
- [ ] Targets configured: `androidLibrary {}`, `iosArm64()`, `iosSimulatorArm64()`
- [ ] Code moved to `commonMain` / `androidMain`; `expect`/`actual` for platform APIs
- [ ] Dependencies in correct source sets (`commonMain` vs `androidMain` vs `iosMain`)
- [ ] Tests use `kotlin-test`; shared tests in `commonTest`, platform tests in `androidHostTest`/`iosTest`
- [ ] `./gradlew :<module>:build` and `:<module>:allTests` pass
- [ ] Android app still builds and runs: `./gradlew :app:assembleDebug`

---

## UI Migration (Compose Multiplatform)

- [ ] Theme, design system moved to `commonMain`
- [ ] Resources moved from `res/` to `composeResources/`; `R.*` → `Res.*`
- [ ] Screens and ViewModels migrated to shared code (one at a time)
- [ ] Navigation graph in `commonMain`; platform-specific screens injected where needed
- [ ] Android-specific APIs replaced or wrapped with `expect`/`actual`

---

## iOS Entry Point

- [ ] Xcode project linked to KMP framework
- [ ] Framework builds: `./gradlew :shared:linkDebugFrameworkIosSimulatorArm64`
- [ ] iOS app launches and works
- [ ] Swift interop configured if needed (KMP-NativeCoroutines or SKIE)
- [ ] Umbrella module created if multiple shared modules exist

---

## Final Verification

- [ ] `./gradlew build` succeeds (all modules, all targets)
- [ ] Android app runs with no regressions
- [ ] iOS app builds and runs
- [ ] All tests pass: `./gradlew allTests`
- [ ] No `android.*` / `java.*` imports in `commonMain`
