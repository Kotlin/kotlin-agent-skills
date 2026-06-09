# Framework Exports and Generated Code

## Framework exports

Every exported module grows the API surface the compiler and linker must
keep.

- Remove `transitiveExport = true`. It exports the entire transitive closure
  and disables dead code elimination in many cases — it is almost never what
  the project actually needs.
- Keep an explicit `export(...)` only for modules whose API Swift or
  Objective-C code calls directly.

```kotlin
// Before: exports everything analytics depends on, defeats DCE
binaries.framework {
    export(project(":analytics"))
    transitiveExport = true
}

// After: exports exactly the Swift-facing API
binaries.framework {
    export(project(":analytics"))
}
```

If Swift code stops compiling after narrowing exports, add back only the
specific modules it references — that is the export list the project really
needs.

## Generated code

If `kapt*` or `ksp*` tasks dominate the measured time, report the bottleneck
as generated-code work — do not present a Kotlin/Native tweak as the fix.

- Prefer KSP over kapt when the processor supports it.
- In multiplatform projects, scope KSP to the targets that need it instead of
  a broad `ksp(...)` dependency:

  ```kotlin
  dependencies {
      add("kspCommonMainMetadata", libs.myprocessor)
      add("kspIosSimulatorArm64", libs.myprocessor)
  }
  ```

- If kapt must stay, set `kapt.include.compile.classpath=false` so processors
  are not searched on the whole compile classpath, and propose the KSP
  migration as separate follow-up work.

Docs: https://kotlinlang.org/docs/ksp-multiplatform.html and
https://kotlinlang.org/docs/native-improving-compilation-time.html
