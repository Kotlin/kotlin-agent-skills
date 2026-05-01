---
name: kotlin-language-version-features
description: >
  Kotlin 2.2.0–2.4.0-Beta2 EAP feature availability, stability, and
  enablement. Use for "can I use X in Kotlin 2.y", "is Y stable/default in
  version Z", "what's new in 2.y", "what flag does Z need", or when
  reviewing/writing Kotlin code that depends on a feature whose status
  varies by version (context parameters, backing fields, collection
  literals, annotation targets, name-based destructuring, UUID/time APIs,
  Kotlin/Wasm, Kotlin/JS export, Swift export, Gradle/Maven plugin, Compose
  compiler, etc.). Separates each feature's stability from its enablement
  mode (default/flag/opt-in) for a given target version. Not for Kotlin
  ≤2.1.x and not for deprecation/removal queries.
license: Apache-2.0
metadata:
  author: JetBrains
  version: "1.0.0"
  verified: "2026-05-01"
---

# Kotlin Language Version Features

Use this skill to answer whether Kotlin 2.2, 2.3, or 2.4 EAP language,
standard library, compiler, platform, or build-tool features are available for
a target project, and how to enable or avoid them.

## Scope

- Covers Kotlin 2.2.0 through 2.4.0-Beta2 EAP (specifically: 2.2.0, 2.2.20,
  2.3.0, 2.3.20, 2.3.21, 2.4.0-Beta2). Kotlin 2.4.0 final is unreleased as
  of the verified date.
- Source corpus: official Kotlin "What's new" documentation (links per capsule).
- Does not cover third-party libraries except where Kotlin tooling or platform
  interop documentation mentions them.

## Reference files

Load only the smallest useful file:

- Status-only feature lookup: [status-index.md](references/status-index.md)
- Kotlin 2.2.x: [kotlin-2.2-feature-guide.md](references/kotlin-2.2-feature-guide.md)
- Kotlin 2.3.x: [kotlin-2.3-feature-guide.md](references/kotlin-2.3-feature-guide.md)
- Kotlin 2.4 EAP: [kotlin-2.4-eap-feature-guide.md](references/kotlin-2.4-eap-feature-guide.md)
- Build flags / API symbols: [symbol-map.md](references/symbol-map.md)
- Search hints (grep patterns, conceptual aliases): [search-hints.md](references/search-hints.md)

Each capsule has one canonical home (usually the file matching its `id`
prefix; exceptions exist). Stub entries appear as `### id:` capsules with a
`Canonical capsule:` pointer, and in `status-index.md` as `**stub → <file>**`
notes. If a stub answers the user's question, stop; otherwise follow the
pointer.

## Stability and Modes

Treat feature status as two independent axes:

- **Stability / maturity** answers whether Kotlin documents the feature as
  `stable`, `eap-stable`, `experimental`, `alpha`, `beta`, `preview`, or just a
  documented behavior/change with no explicit stability label.
- **Mode / enablement** answers how the feature is used: `default/no flag`,
  compiler flag, language-version preview, opt-in annotation, Gradle/Maven DSL,
  binary property, configurable mode, runtime behavior, or generated tooling
  behavior.

`default` is not a stability label. It means a behavior or mode is enabled
automatically in the stated Kotlin version. A stable feature can have a default
mode, and a pre-stable feature can also be enabled by default. Always report
both axes when answering a feature-status question.

Stability labels:

- `stable`: the Kotlin docs mark the feature/API stable in a released version.
- `eap-stable`: the 2.4.0-Beta2 EAP docs mark it stable, but final 2.4.0 is
  not verified here.
- `experimental`, `alpha`, `beta`, `preview`: pre-stable; use only when the
  project accepts churn and the required mode is already enabled or approved.
- `documented behavior`: documented change with no explicit stability label;
  use the capsule notes and target version rather than inventing a stability
  promise.

## Lookup priority

[status-index.md](references/status-index.md) is the **sole source of truth
for stability and mode** for every covered feature. Use it for any query
that does not require a usage example or enablement snippet — that includes
status checks ("is X stable in 2.3?"), flag/mode questions ("what flag does
Y need?"), and delta surveys ("what's new in 2.3.20?", filter the matching
section by the `Version` column). Version-guide files no longer carry their
own status tables.

Load `kotlin-X-feature-guide.md` only when the user's request needs a
usage example, an enablement snippet, agent notes, or a source URL. Each
capsule starts at `### id: <kt2x-...>` and runs to the next `### id:`. Stub
capsules carry a `Canonical capsule:` pointer; follow it when the
status-index row alone is not enough.

For "how did X progress across versions" questions, grep `status-index.md`
for the capsule id — it appears once per version section that covers it.

## Mode selection

| User intent | Mode | References |
|---|---|---|
| "Can I use this in Kotlin 2.3?" | Capability (cumulative) | 2.2 + 2.3 |
| "What can Kotlin 2.4 EAP use?" | Capability | 2.4 guardrails first, then 2.2 + 2.3 + 2.4 EAP |
| "What's new in Kotlin 2.3?" | Delta | 2.3 |
| "Compare 2.2 and 2.3" | Delta/comparison | 2.2 + 2.3 |

## Platform-scope filter

Use this only when the user asks what applies to a project, or when generating
code/config. For broad release surveys, do not ask a platform question; include
or group platform-specific rows instead. If the project platform is unknown and
the answer would change, ask.

| Project type | Relevant `Area` prefixes | Skippable prefixes |
|---|---|---|
| JVM-only application or library | `Language`, `Standard library`, `Compiler`, `JVM /…`, `Gradle /…`, `Maven`, `Compose compiler` (if Compose) | `Native /…`, `Wasm /…`, `JavaScript /…`, `Multiplatform /…` (unless KMP) |
| Kotlin Multiplatform | all relevant target platforms + `Multiplatform /…` | none — any `Area` may apply |
| Android (Compose) | JVM-only set + `Compose compiler` | same as JVM-only |
| Kotlin/JS only | `Language`, `Standard library`, `Compiler`, `JavaScript /…`, `Gradle /…` | `JVM /…`, `Native /…`, `Wasm /…` |
| Kotlin/Native only (incl. iOS) | `Language`, `Standard library`, `Compiler`, `Native /…`, `Gradle /…` | `JVM /…`, `JavaScript /…`, `Wasm /…` |
| Kotlin/Wasm only | `Language`, `Standard library`, `Compiler`, `Wasm /…`, `Gradle /…` | `JVM /…`, `Native /…`, `JavaScript /…` |

`Language`, `Standard library`, and `Compiler` rows always apply. Build
tooling (`Gradle /…`, `Maven`) applies based on the build system in use.

**Out of scope:**

- **Kotlin ≤2.1.x.** This skill starts at 2.2.0. For features in 2.0/2.1,
  redirect to the upstream Kotlin "What's new" pages (`whatsnew21.html`,
  `whatsnew20.html`, etc.). Do not infer 2.1 status from this skill's 2.2
  capsules — many features evolved between those releases.
- **Deprecation/removal queries** ("what was deprecated/removed in Kotlin
  X?"). The status index describes what *exists*; it does not enumerate
  removals (e.g., 2.3.0 removed language versions 1.8 and 1.9 on non-JVM,
  and the Ant build system). Point the user at the upstream "What's new"
  page.

## Recipe

1. Identify the target Kotlin version (from the user, or from build files
   per the cheat sheet below). If it cannot be inferred, ask — do not
   default to latest or EAP. Pick capability or delta mode.

   Version-detection cheat sheet:

   - `build.gradle.kts` plugins block: `kotlin("jvm") version "2.3.0"`,
     `kotlin("multiplatform") version "..."`, etc. Plugin version =
     compiler version.
   - `settings.gradle.kts` `pluginManagement { plugins { ... } }` may pin
     the Kotlin plugin version centrally.
   - `gradle/libs.versions.toml`: a `[versions]` entry like
     `kotlin = "2.3.20"` referenced by a plugin/library entry.
   - `gradle.properties`: occasionally `kotlinVersion=...` or
     `kotlin.version=...`.
   - `pom.xml`: `<kotlin.version>...</kotlin.version>` property and the
     `kotlin-maven-plugin` `<version>`.

   Version lenses:

   - **Language syntax/semantics** need a compiler new enough for the feature
     and an effective `languageVersion` that is not pinned below the feature's
     language release. A `languageVersion` / Maven `<languageVersion>` setting
     cannot enable syntax from a newer compiler.
   - **Standard library APIs** need the matching `kotlin-stdlib` dependency and
     an effective `apiVersion` that does not hide the API. Check explicit
     stdlib dependencies if the project overrides the plugin default.
   - **Compiler flags and diagnostics** follow the Kotlin compiler version.
   - **Gradle/Maven/plugin behavior** follows the Kotlin Gradle or Maven plugin
     version, not just the source language level.

2. **If the target is Kotlin 2.4.x (any EAP build):** load
   `kt24-eap-guardrails` from
   [kotlin-2.4-eap-feature-guide.md](references/kotlin-2.4-eap-feature-guide.md)
   *before* answering. Always say "Kotlin 2.4.0-Beta2" or "2.4 EAP" rather
   than "Kotlin 2.4". Treat `eap-stable` as advisory, not as final-GA
   stability. For production projects, prefer Kotlin 2.3.x stable unless
   the user explicitly wants EAP features or is already on an EAP train.

3. Look the feature up in `references/status-index.md`. For capability-mode
   queries, scan the in-scope version sections; for delta-mode queries,
   scan only the matching version section and filter rows by the `Version`
   column. If the same id appears in multiple in-scope sections, take the
   row for the highest target version not newer than the user's.

   Patch filtering: exclude rows whose first concrete version is newer than
   the target (`2.3.0` excludes `2.3.20` rows; `2.2.0` excludes `2.2.20`
   rows). Treat `2.3.21` as `2.3.20` for feature rows because it is covered
   here as a bugfix release with no new feature capsules.
4. If a build flag, Gradle property, or API symbol is the user's starting
   point and the id is not obvious, load
   [symbol-map.md](references/symbol-map.md) for the reverse lookup, then
   return to `status-index.md` for the target-version stability and mode.
5. If the table answer is enough, stop. Otherwise load the canonical
   capsule body from `kotlin-X-feature-guide.md`: for stub rows
   (`**stub → <file>**`), in the named file; otherwise in the file matching
   the id prefix. Use capsule prose for usage, enablement, notes, and source
   URLs only — never for stability/mode.
6. Answer with both axes: e.g., "stable and default", "experimental, requires
   `-Xfoo`", "documented behavior — Kotlin docs give it no explicit
   stability label."

## Answer contract

For feature-status answers, include: target version, availability, stability,
mode/flag/opt-in, and caveat/source when relevant.

Do not silently generate code or config that depends on `experimental`,
`preview`, `alpha`, `beta`, or EAP-only `eap-stable` features. State the
required flag/opt-in and get confirmation, unless the project already uses
that pre-stable feature or the user explicitly asked for it. `stable` and
`documented behavior` rows may be used without extra confirmation.

## Freshness

- Skill `verified` date is in the frontmatter (`metadata.verified`). All
  release dates and EAP claims in this skill were checked then.
- **EAP source URLs are content-mutable.** `whatsnew-eap.html` and any URL
  that does not include a version number can shift between visits. Treat
  capsule status for `kt24-*` and any `eap-stable` entry as advisory once
  `today > verified + 30 days`, and reverify against the upstream doc before
  recommending production code.
- Stable-release URLs (e.g., `whatsnew22.html`, `whatsnew23.html`,
  `whatsnew2320.html`) are treated as immutable for the purposes of this
  skill; reverify only after Kotlin 2.4.0 final ships or upon a known doc
  rewrite.

## Flags & API symbols → capsule id

If reviewing build flags, Gradle properties, or API symbols and the
feature id is not obvious, load [symbol-map.md](references/symbol-map.md).
If the symbol is not listed there, load
[search-hints.md](references/search-hints.md) for grep/rg patterns and
conceptual aliases, or search references directly with
`rg -n "<symbol>" references/*.md`.
