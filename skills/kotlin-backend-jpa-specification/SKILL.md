---
name: kotlin-backend-jpa-specification
description: >
  Build type-safe JPA Specification queries using the jpa-spec-kotlin-dsl library.
  Covers the Specification DSL, PredicateSpecification DSL, and Predicate DSL for
  equality, comparison, string matching, nullability, boolean, inclusion, and
  collection operations. Also covers composing specifications with `and`/`or`,
  type-safe joins, and fetch-joins. Use when the project extends
  JpaSpecificationExecutor or uses PredicateSpecification and builds dynamic
  queries in Kotlin. Prefer this DSL over raw CriteriaBuilder/Root/Path code.
license: MIT
metadata:
  author: Alfonso Ristorato
  version: "1.0.0"
  library: "io.github.alfonsoristorato:jpa-spec-kotlin-dsl"
  repository: "https://github.com/alfonsoristorato/jpa-spec-kotlin-dsl"
  docs: "https://alfonsoristorato.github.io/jpa-spec-kotlin-dsl/"
---

# JPA Specification Kotlin DSL

A Kotlin DSL for building type-safe JPA queries using idiomatic Kotlin syntax.
It replaces raw `CriteriaBuilder`/`Root`/`Path` boilerplate with extension
functions on `KProperty1<T, P>`, giving compile-time safety

## When to Use This DSL

- The project extends `JpaSpecificationExecutor<T>` and builds `Specification` 
  lambdas.
- The project extends `JpaSpecificationExecutor<T>` and builds `PredicateSpecification`
  lambdas.
- Dynamic query construction is needed (e.g. optional filters, search endpoints).

## Installation

### Gradle (Kotlin DSL)
```kotlin
dependencies {
    implementation("io.github.alfonsoristorato:jpa-spec-kotlin-dsl:<version>")
}
```

### Maven
```xml
<dependency>
    <groupId>io.github.alfonsoristorato</groupId>
    <artifactId>jpa-spec-kotlin-dsl</artifactId>
    <version>version</version>
</dependency>
```

## Three DSL Flavors

The library provides three levels of abstraction. Pick the one that fits the use
case:

| DSL                            | Returns                     | When to use                                                                                                             |
|--------------------------------|-----------------------------|-------------------------------------------------------------------------------------------------------------------------|
| **Specification DSL**          | `Specification<T>`          | Standard Spring Data JPA dynamic queries                                                                                |
| **PredicateSpecification DSL** | `PredicateSpecification<T>` | Simpler predicate-only queries (no `CriteriaQuery` access)                                                              |
| **Predicate DSL**              | `Predicate`                 | Building predicates inside existing `Specification {}` or `PredicateSpecification {}` lambdas, or inside join callbacks |

All three share similar (almost always the same) syntax: `Entity::property.operation(value)`.

## Before and After

### Before — raw Criteria API

```kotlin
val spec = Specification<User> { root, _, cb ->
    val namePath = root.get<String>("name")  
    val agePath  = root.get<Int>("age")
    cb.and(
        cb.equal(namePath, "Alice"),
        cb.greaterThan(agePath, 18)
    )
}
repository.findAll(spec)
```

**Problems:**
- `"name"` and `"age"` are raw strings — typos compile but fail at runtime (can be avoided with `KProperty` reference, but boilerplate remains)
- Boilerplate obscures the business rule
- Composing multiple conditions requires manual `cb.and` / `cb.or` wiring

### After — jpa-spec-kotlin-dsl

```kotlin
repository.findAll(User::name.equal("Alice") and User::age.greaterThan(18))
//or
repository.findAll(
    and(
        User::name.equal("Alice"),
        User::age.greaterThan(18)
    )   
)
```


## Operations Reference

### Equality

```kotlin
// equal
User::role.equal("ADMIN")

// notEqual
User::role.notEqual("GUEST")
```

Works with any property type. Nullable properties are handled transparently.

### Comparison

Works with any `Comparable` type:

```kotlin
User::age.greaterThan(17)
User::age.greaterThanOrEqualTo(18)
User::age.lessThan(65)
User::age.lessThanOrEqualTo(64)
User::age.between(18, 65)
```

### String Operations

```kotlin
User::email.like("%@gmail.com")
User::name.notLike("%bot%")
```

Use `%` for wildcard matching as per SQL `LIKE` syntax.

### Nullability

```kotlin
User::email.isNull()
User::email.isNotNull()
```

### Boolean

```kotlin
User::isActive.isTrue()
User::isActive.isFalse()
```

### Inclusion (IN clause)

```kotlin
User::age.`in`(25)
User::role.`in`(listOf("ADMIN", "MANAGER"))
```

The value can be a single element or a `Collection`.

### Collection Operations

```kotlin
Post::tags.isEmpty()
Post::tags.isNotEmpty()
Post::tags.isMember("kotlin")
Post::tags.isNotMember("legacy")
```

## Combining Specifications

### Infix `and` / `or`

```kotlin
val activeAdults = User::isActive.isTrue() and User::age.greaterThanOrEqualTo(18)

val youngOrSenior = User::age.lessThan(25) or User::age.greaterThan(65)
```

Chain as many as needed:

```kotlin
val qualified = User::isActive.isTrue() and
    User::age.greaterThanOrEqualTo(18) and
    User::email.isNotNull()
```

### Variadic `and(…)` / `or(…)`

When combining many specifications, the variadic helpers read more cleanly:

```kotlin
val qualified = and(
    User::isActive.isTrue(),
    User::age.greaterThanOrEqualTo(18),
    User::email.isNotNull()
)

val priority = or(
    User::role.equal("ADMIN"),
    User::role.equal("MODERATOR"),
    User::isPremium.isTrue()
)
```

### PredicateSpecification combiners

The same `and` / `or` infix and variadic functions are available for
`PredicateSpecification<T>`.

## Joins

The DSL supports type-safe joins for querying across entity relationships.

### Single predicate — `joinWithPredicate`

```kotlin
val spec = Comment::user.joinWithPredicate { userJoin, cb ->
    User::name.equal(userJoin, cb, "Alice")
}
repository.findAll(spec)
```

### Multiple predicates — `joinWithPredicates`

Multiple predicates are automatically ANDed:

```kotlin
val spec = Comment::user.joinWithPredicates { userJoin, cb ->
    listOf(
        User::age.greaterThanOrEqualTo(userJoin, cb, 18),
        User::name.equal(userJoin, cb, "Alice")
    )
}
```

### Join types

Pass a `JoinType` to control the join strategy:

```kotlin
Comment::user.joinWithPredicate(JoinType.LEFT) { userJoin, cb ->
    User::name.equal(userJoin, cb, "Alice")
}
```

Defaults to `JoinType.INNER` when omitted.

## Fetch-Joins

Eager-load the joined entity while filtering — same API shape, prefixed with
`fetch`:

```kotlin
// Single predicate
val spec = Comment::user.fetchJoinWithPredicate { userJoin, cb ->
    User::name.equal(userJoin, cb, "Alice")
}

// Multiple predicates
val spec = Comment::post.fetchJoinWithPredicates { postJoin, cb ->
    listOf(
        Post::title.equal(postJoin, cb, "Kotlin DSL"),
        Post::content.like(postJoin, cb, "%specification%")
    )
}
```

Use fetch-joins when the joined data will be accessed immediately to avoid N+1
queries.

## Predicate DSL (Low-Level)

When you need to build `Predicate` objects for use inside an existing
`Specification {}` lambda or a join callback, use the predicate-level functions.
They accept a `Path<T>` (or `From<T, R>`) and a `CriteriaBuilder`:

```kotlin
val spec = Specification<User> { root, _, cb ->
    val namePredicate = User::name.equal(root, cb, "Alice")
    val agePredicate  = User::age.greaterThan(root, cb, 18)
    cb.and(namePredicate, agePredicate)
}
```

This is the same API used inside `joinWithPredicate` / `joinWithPredicates`
callbacks, keeping the syntax uniform across root and join queries.

## Architecture

The library is layered:

1. **Predicate DSL** (`predicate.*`) — extension functions on `KProperty1` that
   take a `Path`/`From` + `CriteriaBuilder` and return a `Predicate`.
2. **Specification DSL** (`specification.*`) — wraps the predicate functions
   into `Specification<T>` lambdas.
3. **PredicateSpecification DSL** (`predicatespecification.*`) — wraps the
   predicate functions into `PredicateSpecification<T>` lambdas.
4. **Join / Fetch** (`join.*`, `fetch.*`) — low-level `KProperty1.join()` and
   `KProperty1.fetch()` helpers.
5. **Specification-level Join / Fetch** (`specification.join.*`,
   `specification.fetch.*`) — convenience wrappers that combine join/fetch with
   predicate building into a single `Specification<T>` or `PredicateSpecification<T>`.

## Common Patterns

### Combining with pagination

```kotlin
val spec = User::isActive.isTrue() and User::role.equal("ADMIN")
val page = userRepository.findAll(spec, PageRequest.of(0, 20, Sort.by("name")))
```

### Reusable specification building blocks

```kotlin
object UserSpecs {
    fun isActive() = User::isActive.isTrue()
    fun hasRole(role: String) = User::role.equal(role)
    fun isAdult() = User::age.greaterThanOrEqualTo(18)
    fun hasEmail() = User::email.isNotNull()
}

repository.findAll(UserSpecs.isActive() and UserSpecs.hasRole("ADMIN") and UserSpecs.isAdult())
```

## Common Traps

- **Missing `JpaSpecificationExecutor`:** Without it on the repository interface, `findAll(Specification)` will not compile.
- **Fetch joins with pagination:** Fetch-joining collections together with `Pageable` triggers an in-memory pagination warning from Hibernate. Make the user aware of this and let them choose if they prefer a two-query approach (ID query + fetch query) for paginated collection joins or accept the in-memory loading.
- **Over-composing in one expression:** For very complex queries with nested AND/OR groups, break them into named intermediate specifications for readability.


## Guardrails

- Always prefer the Specification DSL or PredicateSpecification DSL over raw
  `CriteriaBuilder` code when the library is available.
- Use `KProperty1` references (`Entity::property`) — never pass string-based
  attribute names.
- Use `joinWithPredicate` / `fetchJoinWithPredicate` for joins — do not manually
  call `root.join("name")` with raw strings.
- When building multiple predicates inside a join callback, use
  `joinWithPredicates` (plural) — it ANDs them automatically.
- Use fetch-joins (`fetchJoinWithPredicate`) only when the joined data is needed
  immediately; otherwise use regular joins to avoid unnecessary eager loading.
- Do not mix `Specification` and `PredicateSpecification` in the same query chain — they are separate types.
- Do not use raw `CriteriaBuilder` / `Root.get<>(String)` when the DSL covers the operation.

