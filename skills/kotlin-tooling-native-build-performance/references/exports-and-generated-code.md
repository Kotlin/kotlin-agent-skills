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

If `ksp*` tasks dominate the measured time, report the bottleneck as
generated-code work — do not present a Kotlin/Native tweak as the fix.

- Scope KSP to the targets or source sets that need generated code instead of
  a broad `ksp(...)` dependency:

  ```kotlin
  dependencies {
      add("kspCommonMainMetadata", libs.myprocessor)
      add("kspIosSimulatorArm64", libs.myprocessor)
  }
  ```

- Confirm the generated sources are consumed by the corresponding native
  compilation before adding another target-specific KSP configuration.

Docs: https://kotlinlang.org/docs/ksp-multiplatform.html and
https://kotlinlang.org/docs/native-improving-compilation-time.html
