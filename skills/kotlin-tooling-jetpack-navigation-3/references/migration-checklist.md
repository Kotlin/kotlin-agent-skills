# Navigation 2 to Navigation 3 Migration Checklist

This checklist condenses the official migration order from:

- <https://developer.android.com/guide/navigation/navigation-3/migration-guide>

## Pre-Migration Checks

Inspect the project for:

- custom destination types
- destinations reused across multiple back stacks
- nested navigation deeper than one level
- deep links with synthetic back stack behavior
- bottom navigation or other multiple top-level back stacks

If any of the first three exist, call out that the migration is not a simple mechanical replacement.

## Ordered Migration Steps

1. Add the Navigation 3 dependencies recommended by the current docs.
2. Convert routes into serializable `NavKey` types.
3. Create app-owned classes or state holders that keep and mutate the back stack.
4. Replace `NavController` calls with explicit operations on that state.
5. Move destination registration from `NavHost` into an `entryProvider`.
6. Replace `NavHost` with `NavDisplay`.
7. Remove old Navigation 2 dependencies once the migration is complete.

## Code-Level Translation Guide

Translate these concepts directly:

- string route constants -> `@Serializable` `NavKey` types
- `navController.navigate(...)` -> append or replace entries in app-owned back stack state
- `NavHost(...) { composable(...) }` -> `NavDisplay(...)` with `entryProvider { entry<...> { ... } }`
- navigation arguments parsed from route strings -> typed constructor fields on the key
- graph-local destination declarations -> feature-local entry builder functions

## State and Lifecycle Checks

Verify all of these after migration:

- back stack survives configuration change
- back stack survives process death where the docs expect it to
- destination state is retained with the correct Navigation 3 decorators
- `ViewModel` scope still matches destination lifecycle expectations
- bottom navigation preserves each tab's history if the old app did

## Cleanup Checks

Before finishing:

- remove unused route constants and argument parsing helpers
- remove `NavController` plumbing that no longer owns state
- remove obsolete Navigation 2 dependencies
- re-test back behavior, deep links, dialogs, and tab switching
