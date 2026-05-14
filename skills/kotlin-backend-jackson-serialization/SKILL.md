---
name: kotlin-backend-jackson-serialization
description: >
  Diagnose and design JSON serialization for Kotlin + Jackson in Spring
  applications. Covers tri-state PATCH semantics (distinguishing absent
  from explicit null), jackson-module-kotlin registration, immutable DTO
  design, and date-time handling. Use when DTOs fail to deserialize,
  when PATCH endpoints cannot clear nullable fields, or when ObjectMapper
  changes risk breaking existing API contracts.
license: Apache-2.0
metadata:
  author: JetBrains
  version: "1.0.0"
---

# Jackson Serialization for Kotlin

Kotlin's null-safety and default parameters interact with Jackson in ways that require
deliberate design. The most common trap is PATCH endpoints where `null` means both "field
omitted" and "clear the value" — making it impossible for clients to clear optional fields.

This skill teaches correct Jackson + Kotlin patterns in Spring projects.

## Core Kotlin Rules

- Keep DTOs immutable. Do not switch `val` to `var` just to appease Jackson.
- Do not add empty constructors as a workaround if `jackson-module-kotlin` can model the contract.
- Treat nullable as a wire-contract decision, not a convenient escape hatch.
- Ensure `jackson-module-kotlin` is registered — Spring Boot auto-configures it if on the classpath.

## Tri-State PATCH Semantics

When a PATCH endpoint must distinguish "field omitted" (keep current value) from "field
explicitly set to null" (clear the value), a plain nullable DTO cannot express this.

### Broken: Elvis Operator Conflates Absent and Null

```kotlin
// BROKEN: cannot distinguish omitted from explicit null
data class OrderPatchRequest(
    val notes: String? = null,
    val customerReference: String? = null
)

fun apply(order: Order, request: OrderPatchRequest) {
    order.notes = request.notes ?: order.notes  // explicit null → keeps old value (WRONG)
}
```

Sending `{"notes": null}` deserializes as `null`. Elvis keeps the old value. The field can
never be cleared.

### Correct: Optional Wrapper for PATCH Fields

```kotlin
data class OrderPatchRequest(
    val notes: Optional<String>? = null,       // null = omitted, Optional.empty() = explicit null
    val customerReference: Optional<String>? = null,
    val deliveryAddress: Optional<String>? = null
)
```

### Applying the Patch

```kotlin
fun apply(order: Order, request: OrderPatchRequest) {
    request.notes?.let { opt ->
        order.notes = opt.orElse(null)          // Optional.empty() → null (clears)
    }                                           // null (field omitted) → no change
    request.customerReference?.let { opt ->
        order.customerReference = opt.orElse(null)
    }
    request.deliveryAddress?.let { opt ->
        order.deliveryAddress = opt.orElse(null)
    }
}
```

### How Jackson Deserializes This

With `jackson-module-kotlin` registered:
- Missing field → `null` (the outer `Optional?` is null → field omitted)
- `"notes": null` → `Optional.empty()` (present but empty → explicit null)
- `"notes": "value"` → `Optional.of("value")` (present with value)

## Common Serialization Traps

- Missing field and explicit `null` are not the same. Model tri-state for PATCH.
- Default constructor values can hide client mistakes if the field should have been required.
- `@JsonInclude` may improve payload size but can erase signal clients rely on.
- Sealed classes need stable, versionable type discriminators — not internal detail.
- Enum serialization (by name, code, or custom) is a public compatibility choice.
- Date-time serialization must make timezone assumptions explicit.
- Global `ObjectMapper` changes can break unrelated endpoints. Prefer narrow fixes.

## Design Rules

- Choose one naming strategy and document it.
- Keep transport DTOs separate from persistence entities when contract stability matters.
- If payload evolution matters, favor additive fields and backward-compatible defaults.
- Use separate DTOs for create (all fields required) and patch (all fields optional).

## Guardrails

- Do not use `?:` (Elvis) for PATCH field application — it silently ignores explicit nulls.
- Do not add global mapper behavior for a local one-off issue without considering blast radius.
- Do not hide a contract problem behind `JsonNode` or `Map<String, Any>` unless intentionally untyped.
- Do not forget to register `jackson-module-kotlin` — `Optional` deserialization depends on it.
