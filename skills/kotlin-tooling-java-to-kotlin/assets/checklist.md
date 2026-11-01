# Post-Conversion Verification Checklist

Use this checklist after converting each Java file to Kotlin.

## Compilation & Tests
- [ ] The `.kt` file compiles without errors
- [ ] All existing tests still pass
- [ ] No new compiler warnings introduced

## Semantic Correctness
- [ ] No new side-effects or behavioural changes
- [ ] All public API signatures preserved (method names, parameter types, return types)
- [ ] Exception behaviour unchanged (same exceptions thrown in same conditions)

## Annotations
- [ ] All annotations preserved from the original Java code
- [ ] Annotation site targets correct (`@field:`, `@get:`, `@set:`, `@param:`)
- [ ] No annotations accidentally dropped during conversion

## Imports & Package
- [ ] Package declaration matches original
- [ ] Every import the file still references is present
- [ ] Imports the conversion made dead are gone, as are Java types that shadow Kotlin builtins
- [ ] No new imports beyond what the emitted code needs

## Documentation
- [ ] All Javadoc converted to KDoc format
- [ ] `{@code ...}` → backtick code in KDoc
- [ ] `{@link ...}` → `[...]` KDoc links
- [ ] `<p>` paragraph tags → blank lines
- [ ] `@param`, `@return`, `@throws` tags preserved
- [ ] Class-level and method-level documentation preserved

## Nullability & Mutability
- [ ] Non-null types used only where provably non-null
- [ ] Nullable types (`?`) used for all Java types that could be null
- [ ] `val` used for all immutable variables/properties
- [ ] `var` used only for mutable variables/properties

## Collections
- [ ] `MutableList`/`MutableSet`/`MutableMap` only where the code actually mutates through that reference
- [ ] `List`/`Set`/`Map` for immutable wrappers and never-mutated collections
- [ ] No public signature widened from `List` to `MutableList` (or the equivalent)

## Kotlin Idioms
- [ ] No `getX()` / `setX()` methods remain where a property fits
- [ ] No `!!` left over from platform types
- [ ] No string concatenation where a template reads better
- [ ] No explicit cast after an `is` check
- [ ] No `if/else` chain, or leftover `switch` shape, that a `when` expresses better
- [ ] Scope functions used only where they improved clarity, not sprinkled

## Framework-Specific (check applicable items)
- [ ] **Spring**: Classes that need proxying are `open`; `@Bean` methods are `open`
- [ ] **Lombok**: All Lombok annotations removed; replaced with Kotlin equivalents
- [ ] **Hibernate/JPA**: Entities are `open` (not data classes); no-arg constructor provided
- [ ] **Jackson**: `@field:` and `@get:` annotation site targets correct
- [ ] **RxJava**: Reactive types left in place, or mapped to Coroutines/Flow if that migration was in scope
- [ ] **Mockito**: `when(...)` escaped as `` `when`(...) ``, or MockK used if that migration was in scope
