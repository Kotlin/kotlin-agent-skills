# Kotlin feature symbol map

Maps a build flag, Gradle property, or API symbol to a feature capsule id.
Use this when reviewing `build.gradle.kts`, source imports, or compiler logs
and the feature id is not obvious. This file is **not** a status source:
after mapping an id, load `status-index.md` for the target Kotlin version.

| Flag / symbol | Capsule id |
|---|---|
| `-Xcontext-parameters` | `kt22-context-parameters` |
| `-Xcontext-sensitive-resolution` | `kt22-context-sensitive-resolution` |
| `-Xexplicit-context-arguments` | `kt24-explicit-context-args` |
| `-Xnested-type-aliases` | `kt23-nested-type-aliases` |
| `-Xdata-flow-based-exhaustiveness` | `kt23-data-flow-exhaustiveness` |
| `-Xallow-reified-type-in-catch` | `kt23-reified-catch` |
| `-Xreturn-value-checker` | `kt23-unused-return-value` |
| `-Xname-based-destructuring` | `kt23-name-based-destructuring` |
| `-Xexplicit-backing-fields` | `kt24-explicit-backing-fields` |
| `-Xcollection-literals` | `kt24-collection-literals` |
| `-XXLanguage:+IntrinsicConstEvaluation` | `kt24-compile-time-constants` |
| `-Xannotation-target-all`, `-Xannotation-default-target=param-property` | `kt24-annotation-targets` |
| `-Xannotations-in-metadata` | `kt22-jvm-annotations-metadata` |
| `-Xjvm-expose-boxed` | `kt22-jvm-expose-boxed` |
| `-Xwhen-expressions=indy` | `kt22-jvm-invokedynamic-when` |
| `-Xes-long-as-bigint` | `kt22-js-bigint-long`; `kt23-js-longarray-bigint` |
| `-Xenable-suspend-function-exporting` | `kt23-js-suspend-export` |
| `-Xwarning-level` | `kt22-compiler-warning-level` |
| `-Xallow-contracts-on-more-functions`, `-Xallow-condition-implies-returns-contracts`, `-Xallow-holdsin-contract` | `kt22-contracts` |
| `-Xklib-ir-inliner=...` | `kt24-native-klib-inlining` |
| `kotlin.native.binary.gc=pmcs` | `kt24-native-gc-cms` |
| `kotlin.native.binary.stackProtector` | `kt22-native-memory` |
| `kotlin.native.binary.smallBinary` | `kt22-native-memory` |
| `kotlin.native.binary.latin1Strings` | `kt22-native-memory` |
| `kotlin.native.binary.pagedAllocator` | `kt22-native-memory` |
| `kotlin.uuid.Uuid`, `Uuid.parse` | `kt23-stdlib-uuid` |
| `Uuid.random` | `kt23-stdlib-uuid` |
| `kotlin.time.Clock`, `kotlin.time.Instant` | `kt23-stdlib-time` |
| `kotlin.io.encoding.Base64`, `kotlin.text.HexFormat`, `toHexString` | `kt22-stdlib-codecs` |
| `@JsExport.Default` | `kt23-js-export-defaults` |
| `@JsPlainObject`, `JsPlainObject.copy()` | `kt22-js-export-plain-object` |
| `@JvmExposeBoxed` | `kt22-jvm-expose-boxed` |
| `@all:` use-site target | `kt24-annotation-targets` |
| `field =` accessor (explicit backing field) | `kt24-explicit-backing-fields` |
| `context(...)` declaration | `kt22-context-parameters` |
| `holdsIn`, `returnsNotNull` | `kt22-contracts` |

If a symbol is not listed, search the references with: `rg -n "<symbol>"
references/*.md`.
