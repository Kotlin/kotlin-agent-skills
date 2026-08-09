# Refinement — make converted Kotlin idiomatic & correct

Apply after the structural conversion. The Kotlin you are given is correct but literal: do the full
idiomatic pass over it. **Preserve observable behavior and the public API throughout** — refinement
polishes style and tightens types the structural pass left loose (platform types, nullability), but
never changes what the code does.

Leave alone what is already right. Do not rewrite regions for style where the existing code is already
idiomatic and correct; if it needs no change, emit it unchanged.

## Idiomatic Kotlin
- Getters/setters defined as methods → Kotlin properties; `val` over `var` where never reassigned.
- Nullable types over `!!`; use `?.`, `?:`, and smart casts. Drop redundant null assertions
  (e.g. `Objects.requireNonNull`) once the type is non-null.
- String templates over concatenation; expression bodies for single-expression functions.
- `when` in place of a Java `switch` and of long `if/else` chains — prefer the expression form where
  every branch produces a value; `data class` for value holders; default/named arguments over overloads.
- Scope functions (`let`/`apply`/`also`/`run`/`with`) and lambdas/SAM conversions **only** where they
  improve clarity without changing behavior.

## Correctness & interop (do not regress)
- Tighten the platform types the structural pass left loose — replace `!!` with real nullable or
  non-null types wherever the Java source settles the question.
- Keep annotation **site targets** exactly matching Java: `@field:` / `@get:` / `@set:` / `@param:`.
- Preserve the public API shape; add `@JvmStatic` / `@JvmField` / `@JvmName` / `@JvmOverloads` where Java
  callers rely on the previous static/field/overload shape.
- Keep proxy-based classes/entities `open` where frameworks require it (Spring, Hibernate, …).
- Preserve the package declaration and the KDoc converted from Javadoc. Where the Java source carried
  no documentation, add none.

## Framework specifics
Apply the conventions of whichever frameworks the file actually uses — Spring, Lombok, Hibernate/JPA,
Jackson, Micronaut, Quarkus, Dagger/Hilt, RxJava, JUnit, Guice, Retrofit, Mockito. Converting a file
never swaps one library for another: that is a project-level dependency change, not a refinement.
