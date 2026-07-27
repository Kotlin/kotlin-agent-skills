# Dependency Mapping: Android → KMP Alternatives

This is an advisory reference. Don't swap libraries as part of the KMP migration itself —
flag incompatible dependencies to the user and recommend migrating them as separate tasks
before proceeding with the KMP conversion.

## Core Libraries

| Android Library              | KMP Alternative           | Migration Complexity | Notes                                                                       |
|------------------------------|---------------------------|----------------------|-----------------------------------------------------------------------------|
| `kotlinx-coroutines-android` | `kotlinx-coroutines-core` | Low                  | Drop the `-android` suffix; platform dispatchers are provided automatically |
| `java.time`                  | `kotlinx-datetime`        | Medium               | API differences exist; see [migration notes](#time-migration)               |
| JUnit 4/5                    | `kotlin-test`             | Low                  | Compatible annotations; mostly import changes                               |
| `java.util.UUID`             | `kotlin.uuid.Uuid`        | Low                  | Available in Kotlin 2.0+                                                    |

## Networking

| Android Library | KMP Alternative         | Migration Complexity | Notes                                                          |
|-----------------|-------------------------|----------------------|----------------------------------------------------------------|
| Retrofit        | Ktor Client             | High                 | Different API paradigm; consider KtorFit as a closer API match |
| OkHttp          | Ktor Client             | High                 | Ktor uses platform engines (OkHttp on Android, Darwin on iOS)  |
| Gson            | `kotlinx-serialization` | Medium               | Annotation-based; compile-time safe                            |
| Moshi           | `kotlinx-serialization` | Medium               | Similar annotation model                                       |

## Database

| Android Library | KMP Alternative  | Migration Complexity | Notes                                                                                                            |
|-----------------|------------------|----------------------|------------------------------------------------------------------------------------------------------------------|
| Room (< 2.7.0)  | Room 2.7.0+      | Low                  | Room is KMP-native since 2.7.0; follow [official guide](https://developer.android.com/kotlin/multiplatform/room) |
| SQLDelight      | SQLDelight       | None                 | Already multiplatform                                                                                            |
| Realm           | Realm Kotlin SDK | Low                  | Already multiplatform                                                                                            |

## Dependency Injection

| Android Library | KMP Alternative | Migration Complexity | Notes                                                                                         |
|-----------------|-----------------|----------------------|-----------------------------------------------------------------------------------------------|
| Hilt / Dagger   | Koin            | High                 | Complete rewrite of DI setup                                                                  |
| Hilt / Dagger   | Metro           | Medium               | Supports [interop with Dagger annotations](https://zacsweers.github.io/metro/latest/interop/) |
| Koin 3          | Koin 4          | Low                  | Already multiplatform; minor API updates                                                      |

## Image Loading

| Android Library | KMP Alternative | Migration Complexity | Notes                                                                                            |
|-----------------|-----------------|----------------------|--------------------------------------------------------------------------------------------------|
| Coil 2          | Coil 3          | Low                  | Coil 3 is multiplatform; see [upgrade guide](https://coil-kt.github.io/coil/upgrading_to_coil3/) |
| Glide           | Coil 3          | Medium               | Different API; Glide has no KMP version                                                          |

## UI & Navigation

| Android Library    | KMP Alternative                  | Migration Complexity | Notes                                               |
|--------------------|----------------------------------|----------------------|-----------------------------------------------------|
| Jetpack Compose    | Compose Multiplatform            | Low–Medium           | Most APIs are compatible; resource handling differs |
| Compose Navigation | Compose Multiplatform Navigation | Low                  | Supported in Compose Multiplatform                  |
| Android ViewModel  | Lifecycle ViewModel KMP          | Low                  | Multiplatfrom support available                     | 
| Lottie             | Kottie / Compottie               | Medium               | Third-party ports for JSON animations               |
| Material 3         | Compose Multiplatform Material 3 | Low                  | Available in Compose Multiplatform                  |

## Architecture Components

| Android Library  | KMP Alternative      | Migration Complexity | Notes                                                           |
|------------------|----------------------|----------------------|-----------------------------------------------------------------|
| Paging 3 (< 3.3) | Paging 3.3.0+        | Low                  | Multiplatform since 3.3.0                                       |
| DataStore        | DataStore KMP        | Low                  | Multiplatform support available                                 |
| WorkManager      | No direct equivalent | —                    | Stays in `androidMain`; use platform-specific scheduling on iOS |

## Logging & Analytics

| Android Library    | KMP Alternative     | Migration Complexity | Notes                            |
|--------------------|---------------------|----------------------|----------------------------------|
| Timber             | Kermit / Napier     | Low                  | Multiplatform logging libraries  |
| Firebase Analytics | Firebase Kotlin SDK | Medium               | Community-maintained KMP wrapper |

## Reactive Streams

| Android Library   | KMP Alternative        | Migration Complexity | Notes                                   |
|-------------------|------------------------|----------------------|-----------------------------------------|
| RxJava / RxKotlin | Coroutines + Flow      | High                 | Different paradigm; significant rewrite |
| LiveData          | StateFlow / SharedFlow | Low                  | Kotlin alternative                      |

---

## Time Migration

The `java.time` → `kotlinx-datetime` migration deserves special attention because time calculations often permeate the codebase.

Key API mappings:

| `java.time`                     | `kotlinx-datetime`                  |
|---------------------------------|-------------------------------------|
| `Instant.now()`                 | `Clock.System.now()`                |
| `LocalDateTime`                 | `kotlinx.datetime.LocalDateTime`    |
| `LocalDate`                     | `kotlinx.datetime.LocalDate`        |
| `ZoneId`                        | `kotlinx.datetime.TimeZone`         |
| `Duration`                      | `kotlin.time.Duration`              |
| `Instant.toEpochMilli()`        | `Instant.toEpochMilliseconds()`     |
| `LocalDate.parse("2024-01-01")` | `LocalDate.parse("2024-01-01")`     |
| `instant.atZone(zone)`          | `instant.toLocalDateTime(timeZone)` |

Note: `kotlinx-datetime` intentionally has a smaller API surface than `java.time`. Complex calendar operations may need to stay in platform-specific code.

## Using klibs.io

For dependencies not listed here, check [klibs.io](https://klibs.io) to search for
multiplatform alternatives. It indexes KMP-compatible libraries and helps evaluate options.
