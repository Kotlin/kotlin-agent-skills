# Conversion Methodology

You are a senior Kotlin engineer and Java-Kotlin JVM interop specialist. Your task here is the
**structural translation** of Java into correct, behavior-preserving Kotlin: faithful semantics,
correct nullability and mutability, correct collection types. Idiomatic polish is a separate pass.

## The 3-Step Structural Translation Process

Work through these three steps in order, then emit the finished Kotlin file.

### Step 1: Faithful 1:1 Translation

Make the Kotlin a faithful 1:1 translation of the Java, replicating its semantics and logic exactly.
If you already have a Kotlin version, correct it where it is unfaithful rather than rewriting it.

**Rules:**
- Java classes that are implicitly open MUST be converted as Kotlin classes that are
  explicitly `open`, using the `open` keyword.
- To convert Java constructors that inject into fields, use the Kotlin primary
  constructor. Any further logic within the Java constructor can be replicated with the
  Kotlin secondary constructor.

### Step 2: Nullability & Mutability

Check that mutability and nullability are correctly expressed in your Kotlin conversion.
Only express types as non-null where you are sure that it can never be null, inferred
from the original Java. Use `val` instead of `var` where you see variables that are
never modified.

**Rules:**
- If you see a logical assertion that a value is not null (e.g., `Objects.requireNonNull`),
  this shows that the author has considered that the value can never be null. Use a
  non-null type in this case, and remove the logical assertion.
- In all other cases, preserve the fact that types can be null in Java by using the
  Kotlin nullable version of that type.

### Step 3: Collection Type Conversion

Make sure collection types are expressed correctly in Kotlin.

**Rules:**
- Keep the existing collection types unless they are wrong. Reach for `MutableList` / `MutableSet` /
  `MutableMap` only where the Java code actually mutates the collection through that reference; an
  immutable wrapper (e.g., `Collections.unmodifiableList()`) or a never-mutated collection stays
  `List` / `Set` / `Map`.
- Never widen a public signature from `List` to `MutableList` (or the equivalent for other
  collections) — that is an API change.

Idiomatic transformations (properties, string templates, scope functions, lambdas, …) are **not** part of
this structural process — they belong to the refinement pass.

## The Invariants

These must hold in the emitted result. Check them before you emit; if one is broken, fix it.

**Invariant 1:** No new side-effects or behaviour.

**Invariant 2:** Preserve all annotations and targets exactly.
- Annotations must target the backing field in Kotlin where they targeted the field in
  Java. Use annotation site targets: `@field:`, `@get:`, `@set:`, `@param:`.

**Invariant 3:** Preserve the package declaration, and keep imports correct.
- Keep every import the emitted code still references, and add the ones it newly needs.
- Drop imports the conversion made dead, and imports that would shadow Kotlin names
  (e.g., `java.util.List` shadows Kotlin's `List`).

**Invariant 4:** Preserve the documentation that exists — and only that.
- Convert Javadoc comments to KDoc, carrying the information forwards where structure changes.
- Where the Java source has no Javadoc, **invent none**: no KDoc, no inline comments, no block
  comments, no notes about the conversion itself.

**Invariant 5:** Preserve the public API.
- Do not rename declarations, remove overloads, narrow visibility, or change inheritance semantics.

**Invariant 6:** Do not churn.
- Leave what is already correct exactly as it is. Do not rewrite large unchanged regions for style
  alone. If nothing in the file needs changing, emit it unchanged.

**Invariant 7:** Ensure the output result is in Kotlin.
- The emitted code must be syntactically valid Kotlin.

---

> The walkthroughs below show the intermediate stages for illustration, and continue past the 3
> structural steps into a **Refinement** stage (idioms) to show the finished Kotlin end-to-end.
> Refinement is not part of this doc's structural process, and the intermediate stages are not
> something you emit — emit only the final file.

## Example 1: Utility Class with Nullability

### Java Input

```java
package com.acme.util;

import java.time.LocalDate;

/**
* Utility for printing a greeting that includes the current date.
*/
public class DateGreeter {
  /**
  * Prints a greeting for the given name and the current date.
  *
  * @param name an optional name; if {@code null}, the greeting uses {@code "Guest"}
  */
  public static void greet(String name) {
    String who = (name != null) ? name : "Guest";
    System.out.println("Hello, " + who + " - today is " + LocalDate.now());
  }
}
```

### Conversion Walkthrough

**Step 1** — Faithful translation. The DateGreeter class is implicitly open, the
`greet` method is static → companion object. Javadoc converted to KDoc.

```kotlin
package com.acme.util

import java.time.LocalDate

/**
* Utility for printing a greeting that includes the current date.
*/
open class DateGreeter {
  companion object {
    /**
    * Prints a greeting for the given [name] and the current date.
    *
    * @param name an optional name; if `null`, the greeting uses `"Guest"`
    */
    fun greet(name: String?) {
      var who = if (name != null) name else "Guest"
      println("Hello, " + who + " - today is " + LocalDate.now())
    }
  }
}
```

**Step 2** — The `String?` is correct since the author checks for null. The `who`
variable is only read, so change `var` → `val`.

```kotlin
// Same as above but with:
val who = if (name != null) name else "Guest"
```

**Step 3** — No collections in this code. No changes.

**Refinement** — the `greet` function is not tied to any state of
DateGreeter, so move it to a top-level function. Use string templates and the Elvis operator.

```kotlin
package com.acme.util

import java.time.LocalDate

/**
* Prints a greeting for the given [name] and the current date.
*
* @param name an optional name; if `null`, the greeting uses `"Guest"`
*/
fun greet(name: String?) {
  println("Hello, ${name ?: "Guest"} - today is ${LocalDate.now()}")
}
```

---

## Example 2: Domain Model with Annotations

### Java Input

```java
package com.acme.model;

import com.fasterxml.jackson.annotation.JsonProperty;
import javax.annotation.Nullable;
import java.util.Objects;

/**
* Domain model for a user with a required identifier and an optional nickname.
* <p>
* The {@code id} is serialized as {@code "id"} and is required.
* The {@code nickname} may be absent.
*/
public class User {
  /**
  * Stable, non-null identifier serialized as {@code "id"}.
  */
  @JsonProperty("id")
  private final String id;

  /**
  * Optional nickname for display purposes.
  */
  @Nullable
  private String nickname;

  /**
  * Creates a user with the given non-null identifier.
  *
  * @param id required identifier for the user
  * @throws NullPointerException if {@code id} is null
  */
  public User(String id) {
    this.id = Objects.requireNonNull(id, "id");
  }

  /**
  * Returns the identifier serialized as {@code "id"}.
  *
  * @return the user id
  */
  @JsonProperty("id")
  public String getId() {
    return id;
  }

  /**
  * Returns the optional nickname.
  *
  * @return the nickname or {@code null} if absent
  */
  @Nullable
  public String getNickname() {
    return nickname;
  }

  /**
  * Sets the optional nickname.
  *
  * @param nickname the nickname or {@code null} to clear it
  */
  public void setNickname(@Nullable String nickname) {
    this.nickname = nickname;
  }
}
```

### Conversion Walkthrough

**Step 1** — Faithful translation. Class is implicitly open → `open class`.
`@JsonProperty("id")` on the field → `@field:JsonProperty("id")`.
`@JsonProperty("id")` on the getter → `@get:JsonProperty("id")` when converted to
property later. Keep explicit getters/setters at this step for faithfulness.

```kotlin
package com.acme.model

import com.fasterxml.jackson.annotation.JsonProperty
import javax.annotation.Nullable
import java.util.Objects

/**
* Domain model for a user with a required identifier and an optional nickname.
*
* The `id` is serialized as `"id"` and is required.
* The `nickname` may be absent.
*/
open class User {

  /**
  * Stable, non-null identifier serialized as `"id"`.
  */
  @field:JsonProperty("id")
  private val id: String

  /**
  * Optional nickname for display purposes.
  */
  @field:Nullable
  private var nickname: String? = null

  /**
  * Creates a user with the given non-null identifier.
  *
  * @param id required identifier
  * @throws NullPointerException if `id` is `null`
  */
  constructor(id: String) {
    this.id = Objects.requireNonNull(id, "id")
  }

  @get:JsonProperty("id")
  fun getId(): String { return id }

  @Nullable
  fun getNickname(): String? { return nickname }

  fun setNickname(@Nullable nickname: String?) { this.nickname = nickname }
}
```

**Step 2** — `id` is non-null by design (`Objects.requireNonNull` enforces it).
`nickname` is nullable (`@Nullable`). No val/var changes needed beyond what's already
done. Code unchanged.

**Step 3** — No collections. No changes.

**Refinement** — idiomatic Kotlin:
1. Primary constructor with `id` as a `val` property. Apply both `@field:JsonProperty`
   and `@get:JsonProperty` to match both Java annotation targets.
2. Convert `nickname` getter/setter → Kotlin property with `@field:Nullable` and
   `@get:Nullable`.
3. Drop `Objects.requireNonNull` — Kotlin's type system enforces non-null.
4. Drop `import java.util.Objects` — the conversion made it dead (invariant 3). The other two imports
   are still referenced, so they stay.

```kotlin
package com.acme.model

import com.fasterxml.jackson.annotation.JsonProperty
import javax.annotation.Nullable

/**
* Domain model for a user with a required identifier and an optional nickname.
*
* The `id` is serialized as `"id"` and is required.
* The `nickname` may be absent.
*
* @property id stable, non-null identifier serialized as `"id"`
* @property nickname optional nickname for display purposes; may be `null` if not set
*/
open class User(
  @field:JsonProperty("id")
  @get:JsonProperty("id")
  val id: String
) {
  @field:Nullable
  @get:Nullable
  var nickname: String? = null
}
```
