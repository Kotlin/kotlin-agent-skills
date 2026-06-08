---
name: kotlin-tooling-immutable-collections-0-5-x-migration
description: >
  Migrate Kotlin (and Java) code from kotlinx.collections.immutable 0.3.x / 0.4.x to the
  latest 0.5.x. The 0.5.x line renames every copy-returning method on PersistentList /
  PersistentMap / PersistentSet / PersistentCollection to a participial form per KEEP-0459
  (add→adding, removeAt→removingAt, set→replacingAt, put→putting, clear→cleared, …) and
  deprecates the old names (WARNING, with ReplaceWith). Driven by the compiler: bump the
  version, recompile, and apply the rename each deprecation warning names. Use when the user
  mentions kotlinx.collections.immutable 0.5.x, PersistentList migration, "Use adding()
  instead", KEEP-0459, or sees deprecation warnings from kotlinx.collections.immutable.
license: Apache-2.0
metadata:
  author: JetBrains
  version: "2.4.0"
---

# kotlinx.collections.immutable 0.5.x Migration

The 0.5.x line renames every copy-returning method on the persistent collections to a
participial form (per [KEEP-0459]) and deprecates the old names at `WARNING` level with a
`ReplaceWith` hint. Migrating is a mechanical, binary-compatible, semantics-preserving
call-site rename — same parameters, order, and return type; only the name changes.

Drive it from the compiler: bump the version, recompile, and fix each deprecation warning —
the warning names the replacement. Source of truth: [`0.5.0-MIGRATION.md`].

## When it applies

Check the version the project currently uses:

- **0.3.x or 0.4.x** (any pre-0.5.0) → run the migration below.
- **On 0.5.x but not the latest** → set the version to the latest 0.5.x and stop. All 0.5.x
  releases share the same renames, so a within-line bump adds no new deprecations and needs
  no recompile.
- **On the latest 0.5.x, or on 0.6.x and later** → nothing to do.

## Migration

### 1. Find the build command

Check `README.md`, `CLAUDE.md`, or `AGENTS.md` for how the project builds; if it isn't
written down, infer it from the build files — Gradle (`./gradlew`), Maven (`mvn`, or the
`./mvnw` wrapper), Bazel
(a `bazel` wrapper), or a custom script. Record the compile command (and the test command).
In a multi-module project you only need the modules that use the library, plus any you
change — not a whole-repo build.

### 2. Baseline compile

Compile on the current version and confirm it's green. If it doesn't build now, you can't
tell post-migration errors from pre-existing ones — get a working compile command first.

### 3. Bump to the latest 0.5.x

Find where the version is pinned — `grep -rn kotlinx-collections-immutable` across the build
files finds it (version catalog, build script, `gradle.properties`, `pom.xml`, …) — and set
it to the latest 0.5.x on [Maven Central] (a `-beta` is fine). If the build pins artifact
hashes (e.g. `gradle/verification-metadata.xml`), update those too — the cheapest fix is to
copy the new artifact's checksum straight from the dependency-verification failure message
and add just that one entry, rather than regenerating the whole metadata file. The bump is
binary-compatible; old code keeps compiling with warnings. (If the dependency fails to
resolve with a Kotlin metadata-version error, the project's Kotlin is too old for the 0.5.x
artifact — bump Kotlin first.)

### 4. Recompile and fix the warnings

Recompile. Each renamed method carries `@Deprecated(WARNING, ReplaceWith(...))`, so the
compiler emits one warning per call site naming the replacement (e.g. *"Use removingAll()
instead"*). Apply that rename. Repeat compile → fix until no `kotlinx.collections.immutable`
deprecation warnings remain. (For multiplatform, one target compile surfaces the shared call
sites. Pre-existing factory deprecations such as `immutableListOf` → `persistentListOf`
appear the same way — apply those too.) A recompile that fails right after the bump is
failing *on these deprecations* (plus, if hashes are pinned, a one-time dependency-verification
error) — keep applying the renames the warnings name; don't re-run dependency-resolution or
metadata-regeneration commands to try to clear it.

**Trust the compiler — never find/replace by name.** The same method names exist on
`MutableList` / `MutableMap` / `MutableSet` and on the `.Builder` types, which mutate in
place and are *not* deprecated. Only the sites the compiler flags (receiver statically
`Persistent*`) get renamed; if it didn't flag it, leave it.

**An `Unresolved reference` after a rename means the participial name isn't on that
receiver — you've split a rename.** A rename only compiles if the *declaration* and *every*
call site move together. The library already did that for the kotlinx types, so renaming
their call sites just works — but it doesn't hold for anything else that merely shares the
names. When a renamed call won't resolve, there are two cases:

- The receiver is unrelated to this library (a `Mutable*`, a `.Builder`, a same-named method
  on some other type) — the rename was wrong; revert that site.
- The receiver is a project type the codebase is itself migrating — it implements a
  `Persistent*`, or it's the project's own wrapper whose methods echo these names and get
  renamed to match. The rename is right but *half-done*: rename the declaration and its
  other callers too, so the call resolves. (Deprecated overrides on an implementer are
  step 5.)

Decide by the receiver's *declared* type, never the method name — a `Persistent*`-named
field may hold another type. This matters most when you can't lean on a fast recompile and
are renaming from reading the source.

**Java callers.** The recompile flags them only if the build reports javac deprecation
warnings (`-Xlint:deprecation`, usually off). If it doesn't, grep the `.java` files that
import the library for the old names and rename the calls whose receiver is a `Persistent*`
type.

After the renames, the compiler may report some `@Suppress("DEPRECATION")` as having no
effect — remove those (re-read the region first, in case it still covers something else).

### 5. Custom implementers

If the project has classes that implement `PersistentList` / `PersistentMap` /
`PersistentSet` / `PersistentCollection`, their deprecated overrides need migrating too.
Find them:

```bash
grep -rnE --include='*.kt' \
  '(class|object|interface)\s+\w[^:]*:\s*[^{]*\b(PersistentList|PersistentMap|PersistentSet|PersistentCollection)\s*<' .
```

On Windows PowerShell, `Select-String` is the `grep` equivalent:

```powershell
Get-ChildItem -Recurse -Filter *.kt |
  Select-String '(class|object|interface)\s+\w[^:]*:\s*[^{]*\b(PersistentList|PersistentMap|PersistentSet|PersistentCollection)\s*<'
```

(Confirm a match really lists the interface as a *supertype*, not just a field type or type
argument.) For each, move the implementation into the new participial method and have the
deprecated override delegate to it:

```kotlin
override fun adding(element: E): MyList<E> = /* real implementation */

@Suppress("OVERRIDE_DEPRECATION")
override fun add(element: E): MyList<E> = adding(element)
```

If the participial methods call each other, route those calls through participial siblings,
not the deprecated names. (Add `"DEPRECATION"` to the suppress only when an override body
itself still calls a deprecated member.) Doing this now matters: at 0.6.0 the old names
become compile errors, and at 0.7.0 they are removed. See [`0.5.0-MIGRATION.md`] for the
upstream implementer guidance.

### 6. Run any documented follow-up steps

Do this *after* the renames compile clean, so that if you run low on time the call-site work
is already done. Some projects document steps to run after a dependency change that the
compiler won't surface — most commonly regenerating dependency-verification metadata (the
`gradle/verification-metadata.xml` hashes from step 3). Usually the single-entry fix from
step 3 is all you need; only fall back to the project's documented full-regeneration procedure
(in `README.md` / `CONTRIBUTING.md` / `CLAUDE.md` / `AGENTS.md`) if that one entry isn't
enough. Run it **once** — a full `--write-verification-metadata` / "resolve all dependencies"
pass re-resolves the entire graph and is slow, and repeating it rarely changes the outcome.
Then re-confirm the build is clean.

## Rename reference

- **`PersistentCollection`** — `add`→`adding`, `addAll`→`addingAll`, `remove`→`removing`, `removeAll`→`removingAll`, `retainAll`→`retainingAll`, `clear`→`cleared`
- **`PersistentList`** (the above, plus) — `add(i, e)`→`addingAt`, `addAll(i, c)`→`addingAllAt`, `set(i, e)`→`replacingAt`, `removeAt`→`removingAt`
- **`PersistentMap`** — `put`→`putting`, `putAll`→`puttingAll`, `remove(k)`→`removing`, `remove(k, v)`→`removing`, `clear`→`cleared`

Builders (`PersistentList.Builder`, etc.) are **not** renamed — they mutate in place, so
their imperative names stay.

## Links

- [`0.5.0-MIGRATION.md`] — upstream guide (source of truth, incl. implementer details)
- [KEEP-0459] — naming rationale

[KEEP-0459]: https://github.com/Kotlin/KEEP/blob/main/proposals/KEEP-0459-naming-conventions-for-copy-returning-operations.md
[`0.5.0-MIGRATION.md`]: https://github.com/Kotlin/kotlinx.collections.immutable/blob/master/docs/0.5.0-MIGRATION.md
[Maven Central]: https://central.sonatype.com/artifact/org.jetbrains.kotlinx/kotlinx-collections-immutable/versions
