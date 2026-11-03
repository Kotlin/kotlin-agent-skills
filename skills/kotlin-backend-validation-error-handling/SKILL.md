---
name: kotlin-backend-validation-error-handling
description: >
  Design consistent API validation and error handling for Kotlin + Spring
  services. Covers Kotlin @field: annotation targets for Bean Validation,
  DataIntegrityViolationException to 409 mapping, gateway exception rethrow
  patterns, and @ControllerAdvice design. Use when validation annotations
  are silently ignored, when duplicate-key errors return 500 instead of 409,
  or when gateway timeouts are swallowed by catch-all exception handlers.
license: Apache-2.0
metadata:
  author: JetBrains
  version: "1.0.0"
---

# Validation and Error Handling for Kotlin

Kotlin's annotation target rules interact with Bean Validation in surprising ways: annotations
on constructor parameters target the parameter by default, not the backing field, so validation
is silently skipped. Additionally, common error-handling mistakes include leaking SQL details
via unhandled `DataIntegrityViolationException` and swallowing gateway errors in catch-all blocks.

This skill teaches correct validation and error mapping in Kotlin + Spring projects.

## Kotlin DTO Validation with `@field:` Targets

### Broken: Annotations on Constructor Parameters

```kotlin
// BROKEN: @NotBlank targets the constructor parameter, not the field
data class CreateOrderRequest(
    @NotBlank val customerName: String,  // validation may not trigger
    @Email val email: String
)
```

In Kotlin data classes, annotations on constructor parameters target the **parameter** by default.
Spring's `@Valid` validates **fields** and **getters**, not constructor parameters. Without `@field:`,
validation annotations are silently ignored.

### Correct: `@field:` Target

```kotlin
data class CreateOrderRequest(
    @field:NotBlank val customerName: String,
    @field:Email val email: String,
    @field:Size(min = 1, max = 100) val notes: String? = null
)
```

**Important:** `@field:` is needed for **constructor parameter** properties. Properties declared
in the class body (not in the constructor) already target the field by default and do not need
`@field:`.

### Controller Usage

```kotlin
@PostMapping("/orders")
fun createOrder(@Valid @RequestBody request: CreateOrderRequest): ResponseEntity<Order> { ... }
```

## DataIntegrityViolationException to 409 Conflict

### Broken: Unhandled Constraint Violation

```kotlin
@Service
class UserService(private val userRepository: UserRepository) {
    fun register(request: RegisterRequest): User {
        // If email already exists → DataIntegrityViolationException
        // Without handling → 500 Internal Server Error with SQL details leaked
        return userRepository.save(User(email = request.email, name = request.name))
    }
}
```

### Correct: Two-Layer Handling

```kotlin
// Layer 1: Service — check before save for friendly message
@Service
class UserService(private val userRepository: UserRepository) {
    fun register(request: RegisterRequest): User {
        if (userRepository.existsByEmail(request.email)) {
            throw DuplicateResourceException("User with email '${request.email}' already exists")
        }
        return userRepository.save(User(email = request.email, name = request.name))
    }
}

// Layer 2: ControllerAdvice — catch constraint violation as safety net (race condition)
@RestControllerAdvice
class ErrorHandler {
    @ExceptionHandler(DuplicateResourceException::class)
    fun handleDuplicate(ex: DuplicateResourceException) =
        ResponseEntity.status(409).body(ErrorResponse("DUPLICATE", listOf(ex.message ?: "Already exists")))

    @ExceptionHandler(DataIntegrityViolationException::class)
    fun handleConstraintViolation(ex: DataIntegrityViolationException) =
        ResponseEntity.status(409).body(ErrorResponse("CONFLICT", listOf("Resource conflict")))
}
```

**Why both layers:** Service check provides a friendly message. `@ControllerAdvice` catches race conditions where two requests pass the `existsBy` check simultaneously. Database constraint is the ultimate safety net.

## Gateway Exception Rethrow

### Broken: Catch-All Swallows Gateway Errors

```kotlin
@Service
class PaymentService(private val gatewayClient: GatewayClient) {
    @Transactional
    fun createPayment(request: CreatePaymentRequest): PaymentResponse {
        val payment = paymentRepository.save(Payment(request.customerName, request.amount))
        try {
            val result = gatewayClient.charge(request.amount, request.idempotencyKey)
            payment.status = PaymentStatus.COMPLETED
            payment.gatewayTransactionId = result.transactionId
        } catch (e: Exception) {
            // BUG: catches EVERYTHING including GatewayTimeoutException
            payment.status = PaymentStatus.FAILED
            payment.failureReason = e.message
        }
        paymentRepository.save(payment)
        return toResponse(payment)
    }
}
```

The `catch (e: Exception)` swallows `GatewayTimeoutException`. The `@ControllerAdvice` handler
that maps it to 502/504 never fires. Client sees 200 with FAILED status instead of proper 502/504.

### Correct: Rethrow Gateway-Level Exceptions

```kotlin
@Service
class PaymentService(private val gatewayClient: GatewayClient) {
    @Transactional
    fun createPayment(request: CreatePaymentRequest): PaymentResponse {
        val payment = paymentRepository.save(Payment(request.customerName, request.amount))
        try {
            val result = gatewayClient.charge(request.amount, request.idempotencyKey)
            payment.status = PaymentStatus.COMPLETED
            payment.gatewayTransactionId = result.transactionId
        } catch (e: GatewayTimeoutException) {
            payment.status = PaymentStatus.FAILED
            payment.failureReason = e.message
            paymentRepository.save(payment)
            throw e  // rethrow — let @ControllerAdvice map to 504
        } catch (e: GatewayException) {
            payment.status = PaymentStatus.FAILED
            payment.failureReason = e.message
            paymentRepository.save(payment)
            throw e  // rethrow — let @ControllerAdvice map to 502
        } catch (e: Exception) {
            payment.status = PaymentStatus.FAILED
            payment.failureReason = e.message
        }
        paymentRepository.save(payment)
        return toResponse(payment)
    }
}
```

**Rule:** When catching exceptions to record failure state, rethrow gateway-level exceptions
(timeout, connection refused) so `@ControllerAdvice` maps them to proper HTTP status codes.
Only swallow business-level failures.

## Status Code Rules

- `400` for malformed input, type mismatch
- `401` for authentication, `403` for authorization
- `404` when resource is absent
- `409` for conflicts, optimistic locking, duplicate keys
- `422` for structurally valid but business-invalid payloads
- `502`/`504` for downstream dependency failures
- `500` reserved for genuinely unexpected failures

## Guardrails

- Do not leak stack traces, SQL fragments, or secrets to clients.
- Do not map every domain failure to `400`.
- Do not use `catch (e: Exception)` without rethrowing infrastructure-level errors.
- Do not let `DataIntegrityViolationException` surface as 500 — map to 409.
