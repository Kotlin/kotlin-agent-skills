# Kotlin Compiler Plugins for Gradle

When using Kotlin with frameworks that require compiler plugins (Spring, serialization,
etc.), add them in the `plugins {}` block alongside `kotlin("jvm")`.

## Spring (all-open)

Spring requires classes and certain members to be non-final. The `plugin.spring`
compiler plugin (built on `all-open`) handles this automatically.

```kotlin
plugins {
    kotlin("jvm") version "2.1.20"
    kotlin("plugin.spring") version "2.1.20"
}
```

The `plugin.spring` plugin automatically opens classes annotated with:
- `@Component`, `@Service`, `@Repository`, `@Controller`
- `@Configuration`
- `@Transactional`
- `@Async`
- `@Cacheable`

## JPA / no-arg

JPA entities require a no-argument constructor. The `plugin.jpa` compiler plugin
(built on `no-arg`) generates one automatically.

```kotlin
plugins {
    kotlin("jvm") version "2.1.20"
    kotlin("plugin.spring") version "2.1.20"
    kotlin("plugin.jpa") version "2.1.20"
}
```

The `plugin.jpa` plugin generates no-arg constructors for classes annotated with:
- `@Entity`
- `@Embeddable`
- `@MappedSuperclass`

## Kotlin Serialization

```kotlin
plugins {
    kotlin("jvm") version "2.1.20"
    kotlin("plugin.serialization") version "2.1.20"
}

dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.8.1")
}
```

## Custom all-open Annotations

To open classes with custom annotations (not covered by `plugin.spring`):

```kotlin
plugins {
    kotlin("jvm") version "2.1.20"
    kotlin("plugin.allopen") version "2.1.20"
}

allOpen {
    annotation("com.example.MyOpenAnnotation")
}
```

## Custom no-arg Annotations

To generate no-arg constructors for custom annotations:

```kotlin
plugins {
    kotlin("jvm") version "2.1.20"
    kotlin("plugin.noarg") version "2.1.20"
}

noArg {
    annotation("com.example.MyNoArgAnnotation")
    invokeInitializers = true  // Optional: make generated constructor call initializers
}
```

## Version Catalog Approach

With a Gradle version catalog, declare all plugins in `gradle/libs.versions.toml`:

```toml
[versions]
kotlin = "2.1.20"

[plugins]
kotlin-jvm = { id = "org.jetbrains.kotlin.jvm", version.ref = "kotlin" }
kotlin-spring = { id = "org.jetbrains.kotlin.plugin.spring", version.ref = "kotlin" }
kotlin-jpa = { id = "org.jetbrains.kotlin.plugin.jpa", version.ref = "kotlin" }
kotlin-serialization = { id = "org.jetbrains.kotlin.plugin.serialization", version.ref = "kotlin" }
```

Then in `build.gradle.kts`:

```kotlin
plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.spring)
    alias(libs.plugins.kotlin.jpa)
}
```

This keeps all Kotlin-related version declarations in one place.

## Groovy DSL

In `build.gradle` (Groovy), use the full plugin IDs:

```groovy
plugins {
    id 'org.jetbrains.kotlin.jvm' version '2.1.20'
    id 'org.jetbrains.kotlin.plugin.spring' version '2.1.20'
    id 'org.jetbrains.kotlin.plugin.jpa' version '2.1.20'
}
```

The `kotlin("...")` shorthand is only available in Kotlin DSL.
