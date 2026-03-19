# Official Sources

This skill was created from the Android Developers Jetpack Navigation 3 skill page:

- <https://developer.android.com/guide/navigation/navigation-3/skill>

Use that page as the source-of-truth index. It links to the official migration guide, core docs,
and code recipes.

## Core Documentation

- Jetpack Navigation 3 skill:
  <https://developer.android.com/guide/navigation/navigation-3/skill>
  High-level map of the Navigation 3 migration guide, core docs, and recipes.
- Navigation 3 overview:
  <https://developer.android.com/guide/navigation/navigation-3>
  Use for the concept map, supported patterns, and links to subtopics such as basics, state,
  metadata, modularization, scenes, and animations.
- Get started:
  <https://developer.android.com/guide/navigation/navigation-3/get-started>
  Use for current setup and dependency guidance.
- Migrate from Navigation 2 to Navigation 3:
  <https://developer.android.com/guide/navigation/navigation-3/migration-guide>
  Use for the official ordered migration steps and the warning signs that make migration more complex.
- Modularize navigation code:
  <https://developer.android.com/guide/navigation/navigation-3/modularize>
  Use when the app separates features into modules or needs DI to assemble entries.

## What to Pull From Each Source

- From the skill page:
  use it to discover the relevant recipe for the current request instead of loading everything.
- From the migration guide:
  use it to replace `NavController`, `NavHost`, and string routes with typed keys, app-owned state,
  `entryProvider`, and `NavDisplay`.
- From get started:
  use it to verify the current dependencies and initial setup before editing Gradle files.
- From modularize:
  use it to split feature `api` and `impl` modules and move entry builders into feature implementation modules.

## Recommended Recipe Categories

The official skill page links recipes for:

- basic API usage
- saveable back stack
- entry provider DSL
- common UI with multiple back stacks
- deep links
- scenes and dialogs
- Material adaptive layouts
- animations
- conditional navigation
- modularization with Hilt or Koin
- `ViewModel` argument passing
- returning results as events or state

Load only the recipes that match the task you are performing.
