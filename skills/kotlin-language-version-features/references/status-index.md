# Kotlin feature status index

**Authoritative source for stability and mode** for every feature this skill
covers. Use this file for any query that does not require a usage example,
an enablement snippet, or capsule notes — that includes status checks
("is X stable in 2.3?"), flag/mode questions ("what flag does Y need?"),
and delta surveys ("what's new in 2.3.20?" — filter the matching section
by the `Version` column).

Patch filtering: exclude rows whose first concrete version is newer than the
target (`2.3.0` excludes `2.3.20` rows; `2.2.0` excludes `2.2.20` rows).
Treat `2.3.21` as `2.3.20` for feature rows.

If the user wants a usage example, an enablement snippet, agent notes, or a
source URL, load the corresponding `kotlin-X-feature-guide.md` and jump to
the matching `### id:` capsule.

## Kotlin 2.2 Features

| id | Area | Version | Stability | Mode | Note |
|---|---|---|---|---|---|
| `kt22-guard-conditions` | Language | 2.2.0 | stable | default/no flag | — |
| `kt22-non-local-break-continue` | Language | 2.2.0 | stable | default/no flag | — |
| `kt22-multi-dollar-strings` | Language | 2.2.0 | stable | default/no flag | — |
| `kt22-context-parameters` | Language | 2.2.0 | preview | `-Xcontext-parameters` | — |
| `kt22-context-sensitive-resolution` | Language | 2.2.0 | preview | `-Xcontext-sensitive-resolution` | — |
| `kt22-contracts` | Language | 2.2.20 | experimental | compiler flags + contract opt-in annotations | — |
| `kt24-annotation-targets` | Language / JVM interop | 2.2.0 | preview | `-Xannotation-target-all` and/or `-Xannotation-default-target=param-property` | **stub → kt24 EAP file** |
| `kt23-nested-type-aliases` | Language | 2.2.0 | beta | `-Xnested-type-aliases` | **stub → kt23 file** |
| `kt23-data-flow-exhaustiveness` | Language | 2.2.20 | experimental | `-Xdata-flow-based-exhaustiveness` (not LV 2.3 preview) | **stub → kt23 file** |
| `kt23-expression-body-return` | Language | 2.2.20 | preview | `-language-version 2.3` preview | **stub → kt23 file** |
| `kt23-reified-catch` | Language | 2.2.20 | experimental | `-Xallow-reified-type-in-catch` | **stub → kt23 file** |
| `kt22-stdlib-codecs` | Standard library | 2.2.0 | stable | default/no opt-in for stabilized APIs | Base64 + HexFormat (HexFormat introduced 1.9.0) |
| `kt22-stdlib-experimental-misc` | Standard library | 2.2.20 | experimental | API opt-in annotations where required | `KClass.isInterface`, atomic update helpers, `copyOf` overloads |
| `kt22-compiler-warning-level` | Compiler | 2.2.0 | experimental | `-Xwarning-level=DIAGNOSTIC_NAME:(error\|warning\|disabled)` | — |
| `kt22-jvm-default` | JVM / Compiler | 2.2.0 | stable | default mode `enable`; configurable modes `enable`, `no-compatibility`, `disable` | Default changed `disable` → `enable` in 2.2.0 |
| `kt22-jvm-annotations-metadata` | JVM / Metadata | 2.2.0 | experimental | `-Xannotations-in-metadata`; reader APIs need opt-in | — |
| `kt22-jvm-expose-boxed` | JVM / Java interop | 2.2.0 | experimental | `-Xjvm-expose-boxed` + `@JvmExposeBoxed` | — |
| `kt22-jvm-invokedynamic-when` | JVM / Compiler | 2.2.20 | experimental | `-Xwhen-expressions=indy` + JVM target 21+ | Requires ≥2 conditions besides else; no mutable collections / function types |
| `kt22-mpp-cross-platform-klib` | Multiplatform / Publishing | 2.2.20 | stable | default capability, subject to target compatibility | — |
| `kt22-mpp-common-dependencies` | Multiplatform / Gradle | 2.2.20 | experimental | top-level `kotlin { dependencies { ... } }` | Requires Gradle 8.8+ |
| `kt22-native-swift-export` | Native / Apple interop | 2.2.20 | experimental | Swift export DSL; no language flag | 2.3.0 adds enum + vararg export |
| `kt22-native-memory` | Native / Runtime | 2.2.0 + 2.2.20 | mixed | default allocator + binary properties for allocator/string/small-binary/stackProtector | See capsule for per-version split |
| `kt22-wasm-target-split` | Wasm / Multiplatform | 2.2.0 | alpha-era target model | use `wasmJs` and `wasmWasi` targets | — |
| `kt22-wasm-beta` | Wasm | 2.2.20 | beta | Wasm target DSL; no language flag | — |
| `kt22-js-export-plain-object` | JavaScript / Export interop | 2.2.0 | stable (`copy()`) | default/no flag | — |
| `kt22-js-bigint-long` | JavaScript | 2.2.20 | experimental | `-Xes-long-as-bigint` | Requires ES2020 target |
| `kt22-gradle-abi-validation` | Gradle / Library publishing | 2.2.0 + 2.3.20 | experimental | `kotlin { abiValidation { ... } }` | — |
| `kt22-gradle-compiler-schema` | Gradle / Compiler options | 2.2.20 | documented behavior | schema published by tooling; no project opt-in | — |
| `kt22-gradle-bta` | Gradle / Build tools API | 2.2.0 | experimental | Build Tools API integration path | Usually not user-configured |
| `kt22-maven-daemon` | Maven | 2.2.20 | documented behavior | Maven Kotlin daemon enabled by default | — |
| `kt22-compose-compiler` | Compose compiler | 2.2.0 + 2.2.20 + 2.3.0 | documented behavior | default compiler-plugin behavior | 2.3.0 adds ProGuard mappings (experimental) |

## Kotlin 2.3 Features

| id | Area | Version | Stability | Mode | Note |
|---|---|---|---|---|---|
| `kt23-nested-type-aliases` | Language | 2.3.0 | stable | default/no flag | — |
| `kt23-data-flow-exhaustiveness` | Language | 2.3.0 | stable | default/no flag | — |
| `kt23-expression-body-return` | Language | 2.3.0 | documented behavior | default/no flag | Promoted from 2.2.20 LV-2.3 preview |
| `kt23-reified-catch` | Language | 2.2.20 → 2.3.x | experimental | `-Xallow-reified-type-in-catch` | — |
| `kt23-unused-return-value` | Language / Diagnostics | 2.3.0 | experimental | `-Xreturn-value-checker=check\|full` + `@MustUseReturnValues` / `@IgnorableReturnValue` | — |
| `kt23-name-based-destructuring` | Language | 2.3.20 | experimental | `-Xname-based-destructuring=only-syntax\|name-mismatch\|complete` | — |
| `kt24-explicit-backing-fields` | Language | 2.3.0 | experimental | `-Xexplicit-backing-fields` | **stub → kt24 EAP file** |
| `kt24-annotation-targets` | Language / JVM interop | 2.3.x | preview | `-Xannotation-target-all` and/or `-Xannotation-default-target=param-property` | **stub → kt24 EAP file** |
| `kt23-context-parameter-overload-resolution` | Language | 2.3.20 | documented behavior | default compiler behavior; no opt-in | Compatibility change: overloads with context parameters are no longer treated as more specific |
| `kt22-context-sensitive-resolution` | Language | 2.3.x | experimental | `-Xcontext-sensitive-resolution` | **stub → kt22 file**; 2.3.0 improves sealed/enclosing supertypes + ambiguity warnings |
| `kt22-contracts` | Language | 2.3.x (inherited from 2.2.20) | experimental | compiler flags + contract opt-in annotations | **stub → kt22 file**; no new contract features in 2.3.x |
| `kt23-stdlib-time` | Standard library | 2.3.0 | stable | default/no opt-in | `Clock` and `Instant` |
| `kt23-stdlib-uuid` | Standard library | 2.3.0 | experimental | `@OptIn(ExperimentalUuidApi::class)` or `-opt-in=kotlin.uuid.ExperimentalUuidApi` | parse/format/byte conversion + generation |
| `kt23-stdlib-map-entry-copy` | Standard library | 2.3.20 | experimental | `@OptIn(ExperimentalStdlibApi::class)` or `-opt-in=kotlin.ExperimentalStdlibApi` | — |
| `kt23-jvm-java-versions` | JVM / Toolchain | 2.3.0 | documented behavior | configure `jvmTarget`/toolchain; no feature flag | 2.3.0 = Java 25 bytecode; 2.3.20 docs no JDK change; 2.4.0-Beta2 = Java 26 bytecode |
| `kt23-jvm-nullability-annotations` | JVM / Java interop | 2.3.20 | documented behavior | default warnings; strict via `-Xnullability-annotations=...:strict` | Vert.x annotations supported |
| `kt23-jvm-jpa-plugin` | JVM / Compiler plugin | 2.3.20 | documented behavior | applying `kotlin("plugin.jpa")` auto-applies all-open JPA preset | — |
| `kt23-jvm-lombok` | JVM / Compiler plugin | 2.3.20 | alpha | Lombok compiler plugin | — |
| `kt22-native-swift-export` | Native / Apple interop | 2.3.0 → 2.3.x | experimental | Swift export DSL; no language flag | **stub → kt22 file**; 2.3.0 adds enum-class + vararg export |
| `kt23-native-cinterop-beta` | Native / C and Objective-C interop | 2.3.0 | beta | cinterop use still requires `@ExperimentalForeignApi` for affected APIs | — |
| `kt23-native-cinterop-new-mode` | Native / C interop | 2.3.20 | experimental | cinterop tool option `-Xccall-mode direct` | — |
| `kt23-native-cache-dsl` | Native / Gradle | 2.3.20 | experimental | Gradle Native cache DSL | — |
| `kt23-wasm-fqn` | Wasm / Diagnostics | 2.3.0 | documented behavior | enabled by default for Kotlin/Wasm | Kotlin/Wasm itself is beta as a platform |
| `kt23-wasm-exception-handling` | Wasm / Runtime | 2.3.0 | documented behavior | default for `wasmWasi`; `wasmJs` opt-in via `-Xwasm-use-new-exception-proposal` | Kotlin/Wasm itself is beta as a platform |
| `kt23-wasm-performance` | Wasm / Runtime and compiler | 2.3.0 + 2.3.20 | documented behavior | default compiler/runtime optimizations | 2.3.0 adds Latin-1 + heap reduction; 2.3.20 adds 4.6× string interp, ~5% binary, 65%/21% build-time |
| `kt23-wasm-native-invoke` | Wasm / JS interop | 2.3.20 | experimental | `@nativeInvoke` + Wasm JS interop opt-in | — |
| `kt23-js-suspend-export` | JavaScript / Export interop | 2.3.0 | experimental | `-Xenable-suspend-function-exporting` | — |
| `kt23-js-longarray-bigint` | JavaScript / Export interop | 2.3.0 | experimental | `-Xes-long-as-bigint` | LongArray ↔ BigInt64Array |
| `kt23-js-export-defaults` | JavaScript / Export interop | 2.3.0 | documented behavior | default behavior; use `@JsExport.Default` for ES-module default exports | unified companion access, `@JsStatic` in interfaces, `@JsQualifier` |
| `kt23-js-typescript-declarations` | JavaScript / TypeScript interop | 2.3.20 | experimental | generated declaration behavior for exported interfaces; add TS checks | — |
| `kt23-js-swc` | JavaScript / Build tooling | 2.3.20 | experimental | Kotlin/JS build minifier configuration | — |
| `kt23-gradle-generated-sources-api` | Gradle / Source generation | 2.3.0 | experimental | `KotlinSourceSet` generated sources API | — |
| `kt23-gradle-bta-default` | Gradle / Build tools API | 2.3.20 | documented behavior | Build Tools API enabled by default for **Kotlin/JVM** compilation | other compilation paths not stated to default to BTA |
| `kt23-maven-simplified-setup` | Maven | 2.3.20 | stable | `<extensions>true</extensions>` activates source-root and stdlib smart defaults | — |
| `kt22-compose-compiler` | Compose compiler | 2.3.0 | experimental stack-trace mapping behavior | Compose runtime setting + compiler Gradle plugin mapping output | **stub → kt22 file**; 2.3.0 adds ProGuard mappings for R8-minified apps |

## Kotlin 2.4 EAP Features

| id | Area | Version | Stability | Mode | Note |
|---|---|---|---|---|---|
| `kt24-eap-guardrails` | Release management | 2.4.0-Beta2 | EAP release guardrail | load before giving Kotlin 2.4 guidance | See `metadata.verified` in `../SKILL.md` for the verification date |
| `kt22-context-parameters` | Language | 2.4.0-Beta2 | eap-stable (basic syntax); pre-stable for callable refs and explicit args | default/no flag for basic syntax | **stub → kt22 file** |
| `kt24-annotation-targets` | Language / JVM interop | 2.4.0-Beta2 | eap-stable | default/no flags for `@all` and new defaulting rules | — |
| `kt24-explicit-backing-fields` | Language | 2.4.0-Beta2 | eap-stable | default/no flag | — |
| `kt24-explicit-context-args` | Language | 2.4.0-Beta2 | experimental | `-Xexplicit-context-arguments` | — |
| `kt24-collection-literals` | Language / Standard library interop | 2.4.0-Beta2 | experimental | `-Xcollection-literals` | — |
| `kt24-compile-time-constants` | Language / Compiler | 2.4.0-Beta2 | experimental | `-XXLanguage:+IntrinsicConstEvaluation` | — |
| `kt23-stdlib-uuid` | Standard library | 2.4.0-Beta2 | eap-stable for parse/format/byte APIs; experimental for generation | default for stable surface; `@OptIn(ExperimentalUuidApi::class)` for generation | **stub → kt23 file** |
| `kt24-stdlib-sorted-order` | Standard library | 2.4.0-Beta2 | eap-stable | default/no opt-in | — |
| `kt24-stdlib-unsigned-bigint` | Standard library | 2.4.0-Beta2 | eap-stable | default/no opt-in on JVM | — |
| `kt22-jvm-annotations-metadata` | JVM / Metadata | 2.4.0-Beta2 | documented behavior | compiler writes annotations to metadata by default; metadata consumers still opt into `ExperimentalAnnotationsInMetadata` | **stub → kt22 file** |
| `kt23-jvm-java-versions` | JVM / Toolchain | 2.4.0-Beta2 | documented behavior | set `jvmTarget`/toolchain for Java 26 bytecode | **stub → kt23 file**; EAP page does not document Java 26 annotation processing |
| `kt24-native-swift-package-import` | Native / Apple interop | 2.4.0-Beta2 | no explicit stability label on EAP page | SwiftPM Gradle DSL | Treat as pre-final |
| `kt24-native-swift-flow-export` | Native / Swift export | 2.4.0-Beta2 | no explicit stability label on EAP page | enabled by default for public Swift-exported APIs | — |
| `kt24-native-gc-cms` | Native / Runtime | 2.4.0-Beta2 | documented behavior | CMS GC enabled by default; opt out with `kotlin.native.binary.gc=pmcs` | — |
| `kt24-native-klib-inlining` | Native / Compiler | 2.4.0-Beta2 | documented behavior | intra-module klib inlining default; `-Xklib-ir-inliner=full` for full mode | — |
| `kt24-wasm-incremental` | Wasm / Compiler | 2.4.0-Beta2 | eap-stable | enabled by default; disable with `kotlin.incremental.wasm=false` | — |
| `kt24-wasm-component-model` | Wasm / Interop | 2.4.0-Beta2 | experimental | experimental tooling/sample path | — |
| `kt24-js-value-class-export` | JavaScript / Export interop | 2.4.0-Beta2 | no explicit stability label on EAP page | export `@JvmInline value` classes with `@JsExport` | — |
| `kt24-js-es2015-incremental` | JavaScript / Compiler | 2.4.0-Beta2 | eap-stable | default ES2015 support in JavaScript inlining for incremental builds | — |
| `kt24-maven-jvm-target-alignment` | Maven / JVM | 2.4.0-Beta2 | eap-stable | Maven Kotlin plugin auto-aligns JVM target from Java compiler settings | — |
