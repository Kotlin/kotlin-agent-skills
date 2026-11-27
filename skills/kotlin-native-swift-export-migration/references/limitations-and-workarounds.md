# Limitations, known breakages, workarounds (Kotlin 2.5.0+)

Swift Export is Beta. Official limitations: kotlinlang.org/docs/native-swift-export.html#current-limitations and the
"Adjust unsupported constructs" / "Troubleshooting" sections of the draft migration guide
(`native-swift-export-migration-guide.md`, kotlin-web-site PR #5954; not yet on kotlinlang.org). Re-check
items against the generated Swift of the Kotlin version in use. When something
is missing or broken: (1) find the declaration in `<EXPORT_DIR>/build/SwiftExport/<KOTLIN_TARGET>/files/<Module>/<Module>.{swift,kt}`,
(2) look for `@available(*, unavailable, message: ...)` / `fatalError()` / missing symbols, (3) reshape the
Kotlin API (preferred) or hide the declaration, (4) tell the user what was hidden/changed and why.

## Build breaks

| Symptom | Cause | Workaround |
|---|---|---|
| `compileSwiftExportMainKotlin<Target>`: `e: .../SwiftExport/<KOTLIN_TARGET>/files/<Module>/<Module>.kt: ...` in **your own** module (e.g. `Argument type mismatch: actual type is 'MutableList<Any?>'`) | a declaration uses an unsupported construct, e.g. `MutableList<T>`/`MutableSet<T>`/`MutableMap<K,V>` parameters (mutable collection types are not supported) | change the parameter to read-only `List`/`Set`/`Map`; if the API must stay, hide it with `@HiddenFromObjC` (`kotlin.native.HiddenFromObjC`, opt-in `kotlin.experimental.ExperimentalObjCRefinement`) with a comment. Record the error for the report — worth filing at kotl.in/issue |
| same error with a generic element: `actual type is 'List<Box<Any?>>', but 'List<Box<Profile>>' was expected` | a collection parameter whose element (or value) type is a generic class with a concrete type argument | take `List<OwnType>` and map in Kotlin, or a non-generic wrapper type — `wrapping-generics.md` |
| **Any build error inside a dependency's generated code** (`files/<DepModule>/<DepModule>.kt` or `.swift`, `<DepModule>` ≠ user module) | exporter bug in translating that library, usually only when exported in full | export through the `:ios-export` umbrella (SKILL.md Phase 2, `<EXPORT_MODULE>`); still failing → `hiding-broken-dependencies.md` |
| Generated Swift of the **user's** module fails: `invalid redeclaration of '<name>'` | compiler-plugin-generated public declarations | upgrade the plugin, or make the generated API non-public; replacing the plugin needs the user's permission (SKILL.md Phase 1 step 3) |
| Swift Export worker out of memory | very large exported API | shrink the API surface (`kotlin-api-preparation.md`) or set `kotlin.native.swiftExportWorkerJvmArgs=-Xmx4g` in `gradle.properties` (default `-Xmx1g`) |
| `NoSuchMethodError`/`ClassNotFound` from KSP or a compiler plugin; Kotlin/Native backend crashes | plugin or compiler version | SKILL.md Phase 1; exact cases in `known-issues.md` |
| Gradle configuration errors | see `gradle-and-xcode.md` §6 | |

## Not exported / limited (no build error — the API is just missing or different)

1. **Default argument values** — callers must pass all args; add overloads.
2. **Parameters of generic classes with concrete type arguments** (`Box<String>`, `ScreenState<Profile>`, also in
   function types) — callable missing. `Box<*>`/upper-bound parameters and all return types are fine. Wrap:
   `wrapping-generics.md`.
3. **Generics erased** — no Swift type parameters; cast results (`as!`). F-bounded / multi-bound generics not exported.
4. **`inline` + `reified`** — not exported.
5. **`protected`** — not visible to Swift (incl. Swift subclasses).
6. **`@ShouldRefineInSwift`** — ignored; member exported normally.
7. **Mutable collection types** — not supported as parameters (use read-only); as return types they are opaque
   `any kotlin.collections.MutableList` protocols, not Swift arrays. **Custom types inheriting `List`/`Set`/`Map`**
   may be ignored by the export (KT-80416) and can't be instantiated from Swift (KT-80417) — expose a wrapper.
8. **Map/Set with interface-typed keys** — unavailable.
9. **`kotlin.Array`/primitive arrays** — not generic in Swift and not constructible from Swift (`init` traps);
   create on the Kotlin side or use `List`.
10. **Generic sealed interfaces** — no `sealedType()`; enum classes in sealed hierarchies aren't cases.
11. **Enum classes** lose Kotlin interface conformances in Swift.
12. **Extensions in non-root packages** — static functions with receiver argument, not Swift extensions; extension
    operators are plain functions.
13. **Companion blocks/static extensions (new Kotlin feature)**, `Enum.values()` — not exported (`allCases` works).
14. **Kotlin subclasses of NSObject / Kotlin implementations of ObjC protocols** — not exported.
15. **C structs, C enums, platform typealiases, posix/darwin types** — unavailable.
16. **Member properties named like NSObject properties** (`description`, `debugDescription`, `hash`, `hashValue`,
    `superclass`) — dropped; Swift silently reads the inherited `NSObject` property instead (KT-90497, as designed;
    e.g. a data class `val description: String` returns the object's description). Rename in Kotlin or
    `@ObjCName(swiftName = "description_")`. The scan lists them.
17. **Undeclared exceptions** from non-suspend functions crash the app — add `@Throws`.
18. **No completion-handler variants** of suspend functions.
19. **Hand-written cinterop klib types** are not exported (SwiftPM-import cinterops are).
20. **CocoaPods integration** — not supported; first migrate with the `kotlin-tooling-cocoapods-spm-migration`
    skill (ends on the direct integration with `swiftPMDependencies {}`), as a separate step.
21. **Deployment target** iOS 18+ / macOS 15+ / tvOS 18+ / watchOS 11+ (the generated concurrency support needs
    newer Apple runtime APIs).
22. **Swift can't create Kotlin flows** (or `kotlin.Array`, generic containers) — export typed Kotlin builders
    (`fun mutableStateFlow(initial: String): MutableStateFlow<String>`).
23. **Name clashes with Swift/SwiftUI types**: with `rootPackage`, Kotlin `Shape`, `Color`, `Text`, `Image`, `View`,
    `Hasher`, `Result`, `Error`, `Data`, `Date`, `URL`, `Task`, `Set`... become module-level names and are ambiguous in
    files that also import SwiftUI/Foundation. Rename in Kotlin (or `@ObjCName(swiftName=)`), or qualify in Swift
    (`<BASENAME>.Shape`).
24. Swift **structs/enums can't conform** to Kotlin interfaces (protocols require `KotlinBase`).
25. **No compiler-argument API in the Swift Export DSL** — set options in the module-level `compilerOptions {}`;
    declarations that use opt-in APIs need `compilerOptions { optIn.add("...") }` in the exporting module.
26. **Swift package integration**: `swiftPMDependencies` imports are not supported.

## Runtime traps to test for

| Symptom (console) | Cause | Fix |
|---|---|---|
| `Fatal error: Cannot invoke the inherited implementation of abstract member '...': a Swift subclass must override it` | Swift subclass of a Kotlin abstract class misses an override (compiles fine) | implement every abstract member |
| `... is an abstract class and cannot be instantiated directly` | `AbstractBase()` called | instantiate a subclass |
| `Could not cast value of type 'Swift.Double' to 'Swift.Int'` | Swift integer literal passed to a Kotlin `Any`/`T` parameter becomes `Double` | pass `Int32(x)`; cast back to `Int32` |
| `Could not cast value of type ... to ...` after `as!` on erased generics | wrong assumption about the erased type | use `as?` and inspect; check the Kotlin type (`Int` is `Int32`, `Long` is `Int64`) |
| Kotlin `kotlin.Exception` uncaught / app terminates | exception from non-`@Throws` function | add `@Throws(...)` in Kotlin, handle `catch` in Swift |
| `CancellationError` thrown from `for try await` / `try await` | the Swift Task was cancelled (view disappeared) | `catch is CancellationError {}` — normal |
| `Fatal error` in a user-module function/property that mentions a type of a `HIDDEN` dependency | such declarations are generated as `fatalError()` stubs | replace with a wrapper that doesn't expose the hidden type (`hiding-broken-dependencies.md` §4) |
| `missing sealedType for ...` | a subclass not covered by the generated enum | make the subclass public/exported or handle with casts |

## Obsolete workarounds you may find in older samples (don't copy them)

- `swiftExport { moduleName; flattenPackage; export(...) }` — deprecated DSL (error in Kotlin 2.5.20, removed in 2.6.0); migrate it with `gradle-and-xcode.md` §1b and delete it.
- `(nil as X?)!` placeholders / "Swift can't instantiate KotlinBase subclasses" — Swift classes can subclass
  `KotlinBase` (or an exported Kotlin `open class`, as in the docs) and be instantiated.
- `settings.put(SWIFT_EXPORT_COROUTINES_SUPPORT_TURNED_ON, "true")` — coroutine support is automatic.
- `flow._flow` — use `flow.wrapped` (or better, `asAsyncSequence()`).
- `-Xexport-kdoc` free compiler arg — not needed.
- Post-processing generated Swift in a Gradle `doLast` to delete duplicate stubs — hide the broken dependency
  (`SwiftExportVisibility.HIDDEN`) and wrap it, or fix the Kotlin side.
- Manual `OTHER_LDFLAGS = -l<Module>` — not needed (autolinked); only system libs may be needed.
