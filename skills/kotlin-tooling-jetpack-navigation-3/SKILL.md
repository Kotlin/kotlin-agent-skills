---
name: kotlin-tooling-jetpack-navigation-3
description: >
  Implement or migrate to Jetpack Navigation 3 in Kotlin Android apps built
  with Compose. Covers project setup, serializable NavKey modeling, back stack
  ownership, NavDisplay and entryProvider wiring, state persistence, metadata,
  modularization, and Navigation 2 to Navigation 3 migration. Use when a user
  asks about Navigation 3, NavDisplay, NavKey, entryProvider, multiple back
  stacks, or migrating from NavController and NavHost in a Compose app.
license: Apache-2.0
metadata:
  author: JetBrains
  version: "1.0.0"
---

# Jetpack Navigation 3

This skill is based on the official Android Developers Jetpack Navigation 3 skill:
<https://developer.android.com/guide/navigation/navigation-3/skill>

Use this skill for Compose-first Android apps that are adopting Navigation 3 from scratch
or migrating from Navigation 2 (`NavController`, `NavHost`, and string routes).

## Step 0: Classify the Project

Before changing code, inspect the current navigation setup:

1. Read the app module `build.gradle.kts` or `build.gradle` and confirm the project uses Jetpack Compose.
2. Search for `NavController`, `NavHost`, `composable(`, `navigation(`, `dialog(`, and route strings.
3. Search for `SavedStateHandle`, deep link parsing, bottom navigation, and multiple top-level back stacks.
4. Search for custom `Navigator`, custom destination types, nested graphs deeper than one level, and destinations shared across multiple back stacks.
5. If the app is modularized, identify which modules own navigation keys, destination UI, and navigation orchestration.

### Stop and Call Out Unsupported or High-Risk Cases

The official migration guide explicitly says you should not treat the migration as straightforward when the app has:

- custom Navigation 2 destination types
- destinations reused across multiple back stacks
- nested navigation deeper than one level

If any of those exist, do not mechanically replace APIs. Explain the risk, scope the affected flows,
and migrate incrementally.

## Step 1: Set Up Navigation 3

Follow the current official dependency guidance from the Android docs instead of hardcoding stale versions.
See [official-sources.md](references/official-sources.md) for the source pages to consult.

When implementing Navigation 3:

1. Add the Navigation 3 runtime and UI dependencies recommended by the current docs.
2. Keep all navigation keys serializable and stable.
3. Prefer `@Serializable` `data object` or `data class` types that implement `NavKey`.

Example shape:

```kotlin
@Serializable
data object Home : NavKey

@Serializable
data class Details(val itemId: String) : NavKey
```

## Step 2: Own Navigation State Explicitly

Navigation 3 moves navigation state ownership into your code. Do not recreate a hidden controller layer.

1. Store the back stack in app-owned state.
2. Expose small navigation operations such as `navigateTo(...)`, `replaceAll(...)`, and `goBack()`.
3. Keep navigation mutation logic near the app-level state holder or navigator abstraction.
4. Preserve state across configuration changes and process death using the Navigation 3 state APIs.

### Default Pattern

- Use `rememberNavBackStack(...)` for the active back stack.
- Use `rememberSerializable(...)` for additional custom navigation UI state.
- If the screen content needs `ViewModel`s, wire the official Navigation 3 decorators for saved state and `ViewModelStore` ownership.

### Guardrail

Do not substitute `rememberSaveable` for Navigation 3 serialization APIs when the docs require
`rememberSerializable`. The docs call out `rememberSerializable` as the supported way to persist
custom navigation state.

## Step 3: Replace Route Strings with Typed Keys

When migrating from Navigation 2, convert string routes and argument parsing into typed keys.

1. Replace route constants with `NavKey` types.
2. Move required arguments into the key constructor.
3. Remove string interpolation and manual route parsing where the key type can carry the data directly.
4. Keep keys small. Pass IDs or stable parameters, not large mutable models.

Prefer this:

```kotlin
@Serializable
data class Article(val articleId: Long) : NavKey
```

Over this:

```kotlin
const val ARTICLE_ROUTE = "article/{articleId}"
```

## Step 4: Build an `entryProvider`

Navigation 3 destinations are declared in an `entryProvider`, not a `NavGraph`.

1. Define one `entry<NavKeyType> { ... }` block per destination.
2. Read the typed key in the destination content when arguments are required.
3. Break the provider into feature-specific extension functions as the app grows.
4. Keep feature-local destination builders near the feature implementation code.

Example shape:

```kotlin
val entryProvider = entryProvider {
    entry<Home> {
        HomeScreen()
    }
    entry<Details> { key ->
        DetailsScreen(itemId = key.itemId)
    }
}
```

## Step 5: Replace `NavHost` with `NavDisplay`

For a Navigation 2 migration, the official step order is:

1. add Navigation 3 dependencies
2. make routes implement `NavKey`
3. create classes that hold and mutate navigation state
4. replace `NavController` usage with those classes
5. move destinations from `NavHost` into an `entryProvider`
6. replace `NavHost` with `NavDisplay`
7. remove Navigation 2 dependencies

When rendering:

- pass `entries = backStack.toEntries(entryProvider)` to `NavDisplay`
- connect `onBack` to your navigator or back-stack mutation function
- keep top-level navigation UI state outside destination content when it spans multiple stacks

The full migration checklist is in [migration-checklist.md](references/migration-checklist.md).

## Step 6: Handle Multiple Back Stacks Deliberately

For bottom navigation or other top-level destinations:

1. Keep a separate back stack per top-level tab.
2. Preserve each stack when the user switches tabs.
3. Model the active top-level destination separately from the content back stack if the UI needs it.
4. Use the official multiple-back-stack recipe when the app already has tab history behavior that must be preserved.

Do not flatten multiple tabs into one shared stack unless the app explicitly wants that behavior.

## Step 7: Use Metadata and Scenes Only When the UI Needs Them

Navigation 3 supports metadata-driven behavior such as dialogs, scenes, animations, and custom layout strategies.

Use metadata when:

- a destination should render as a dialog or custom scene
- transitions need to vary by destination
- the app uses adaptive or multi-pane layouts

Do not introduce scenes or metadata wrappers just to mirror a simple full-screen stack.

## Step 8: Modularize Navigation Code

Follow the official modularization guidance when the app has multiple features:

1. Split each feature into `api` and `impl` modules when the project already uses feature modules.
2. Put navigation keys in the feature `api` module.
3. Put destination UI and `EntryProviderScope<NavKey>` builders in the feature `impl` module.
4. Compose the app-wide `entryProvider` from feature entry builders.
5. If many features contribute entries, register builders through DI instead of wiring everything in one file.

This prevents feature UI modules from owning global navigation orchestration while still allowing
cross-feature navigation through typed keys.

## Step 9: Be Precise About Deep Links and Results

When migrating or extending navigation:

1. Convert incoming deep links into typed `NavKey` values as early as possible.
2. If a flow returns results, use one of the official result patterns rather than shared mutable globals.
3. Keep "Up" navigation behavior explicit when building synthetic back stacks for deep links.

If the current app already has complex deep-link reconstruction behavior, verify that behavior before rewriting it.

## Step 10: Check `ViewModel` and Saved State Integration

If destinations use `ViewModel`s:

1. Verify the destination gets the correct key-derived arguments.
2. Verify the `ViewModelStoreOwner` scope matches the intended destination lifecycle.
3. Verify process-death restoration works for both the back stack and destination state.
4. Preserve existing business-state ownership in `ViewModel`s; do not move real domain state into navigation keys.

## Recipes to Load On Demand

Load only the references that match the task:

- [official-sources.md](references/official-sources.md) for the Android documentation map and source links
- [migration-checklist.md](references/migration-checklist.md) for Navigation 2 to 3 replacement work

Also consult the official recipe linked from the Android skill page that matches the current problem:

- basic setup
- saveable back stack
- entry provider DSL
- common UI with bottom navigation and multiple back stacks
- deep links
- dialogs and other scenes
- animations
- conditional navigation
- modularized navigation code with Hilt or Koin
- passing arguments to `ViewModel`
- returning results as events or state

## Guardrails

- Do not keep string routes when typed `NavKey` models are practical.
- Do not keep `NavController` as the hidden source of truth after migrating to Navigation 3.
- Do not move entire screen models through navigation keys.
- Do not introduce deep scene or metadata abstractions for simple full-screen flows.
- Do not assume a Navigation 2 migration is trivial when the app uses custom destinations, reused destinations across stacks, or deep nested graphs.
- Do not hardcode library versions copied from old docs; verify them against the current official page before editing build files.
