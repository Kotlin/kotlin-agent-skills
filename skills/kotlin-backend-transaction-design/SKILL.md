---
name: kotlin-backend-transaction-design
description: >
  Design safe transaction boundaries, rollback behavior, and consistency
  strategies for Kotlin + Spring services. Covers @Transactional propagation
  (REQUIRED vs REQUIRES_NEW), batch processing with atomic error collection,
  optimistic locking with @Retryable, and common Spring transaction traps.
  Use when a feature writes to the database, spans multiple repositories,
  suffers from partial commits, or needs precise transaction boundary design.
license: Apache-2.0
metadata:
  author: JetBrains
  version: "1.0.0"
---

# Transaction Design for Kotlin

Spring's `@Transactional` is easy to add but hard to get right. Common mistakes include
wrong propagation choices (orphaned events, lost audit logs), per-row transactions in batch
processing (partial commits), and optimistic locking without retry logic.

This skill teaches correct transaction boundary design in Kotlin + Spring projects.

## Decision Rules

- Keep one database transaction focused on one consistency boundary.
- Avoid holding a transaction open across external network calls.
- Prefer idempotency keys plus unique constraints for duplicate-request safety.
- Choose locking strategy based on contention: optimistic for low-contention, unique constraints for duplicates, pessimistic only when justified.

## Spring-Specific Checks

- Verify `@Transactional` is on a proxied public entry point.
- Verify self-invocation does not bypass the transaction boundary.
- Verify rollback rules — unchecked exceptions roll back by default, checked may not.
- Verify `readOnly = true` is used only where appropriate.
- Verify `REQUIRES_NEW` is truly required, not masking a design issue.

## Propagation: REQUIRED vs REQUIRES_NEW

### Broken: Wrong Propagation

```kotlin
@Service
class OutboxService(private val outboxRepository: OutboxRepository) {
    @Transactional(propagation = Propagation.REQUIRES_NEW)  // BUG: orphan on rollback
    fun publishEvent(event: OutboxEvent) {
        outboxRepository.save(event)
    }
}

@Service
class AuditService(private val auditRepository: AuditRepository) {
    @Transactional  // BUG: REQUIRED joins caller → lost on rollback
    fun recordFailure(orderId: Long, reason: String) {
        auditRepository.save(AuditEntry(orderId, reason))
    }
}
```

If the outer transaction rolls back:
- OutboxService with REQUIRES_NEW: event is committed separately → **orphaned event**
- AuditService with REQUIRED: audit joins the outer tx → **lost on rollback**

### Correct: Match Propagation to Intent

```kotlin
@Service
class OutboxService(private val outboxRepository: OutboxRepository) {
    @Transactional(propagation = Propagation.REQUIRED)  // joins caller → commits/rolls back together
    fun publishEvent(event: OutboxEvent) {
        outboxRepository.save(event)
    }
}

@Service
class AuditService(private val auditRepository: AuditRepository) {
    @Transactional(propagation = Propagation.REQUIRES_NEW)  // independent → survives rollback
    fun recordFailure(orderId: Long, reason: String) {
        auditRepository.save(AuditEntry(orderId, reason))
    }
}
```

**Rule:** REQUIRED (default) when the operation must succeed or fail with its caller. REQUIRES_NEW when it must persist regardless of caller outcome (audit, logging).

## Batch Processing with Error Collection

### Broken: REQUIRES_NEW Per Row

```kotlin
@Service
class BatchImportService(private val stockRepository: StockLevelRepository) {
    @Transactional(propagation = Propagation.REQUIRES_NEW)  // BUG: each row in its own tx
    fun importRow(row: CsvRow) {
        val stock = stockRepository.findBySku(row.sku)
            ?: throw IllegalArgumentException("Unknown SKU: ${row.sku}")
        stock.quantity += row.quantityChange
        stockRepository.save(stock)
    }

    fun importBatch(rows: List<CsvRow>): BatchImportResult {
        var success = 0
        rows.forEach { row ->
            try { importRow(row); success++ }
            catch (_: Exception) { /* silently skip */ }
        }
        return BatchImportResult(success, rows.size - success)
    }
}
```

Each row commits independently. If row 5 of 10 fails, rows 1-4 are already committed — **partial batch**.

### Correct: Single Transaction, Collect All Errors

```kotlin
@Service
class BatchImportService(private val stockRepository: StockLevelRepository) {
    @Transactional  // single transaction wraps entire batch
    fun importBatch(rows: List<CsvRow>): BatchImportResult {
        val errors = mutableListOf<String>()
        var success = 0

        rows.forEach { row ->
            val stock = stockRepository.findBySku(row.sku)
            if (stock == null) {
                errors.add("Unknown SKU: ${row.sku}")  // collect, don't throw yet
            } else {
                stock.quantity += row.quantityChange
                stockRepository.save(stock)
                success++
            }
        }

        if (errors.isNotEmpty()) {
            throw BatchImportException(
                "Batch failed with ${errors.size} errors: ${errors.joinToString("; ")}"
            )
        }
        return BatchImportResult(success, 0)
    }
}
```

**Rule:** Process ALL rows, collect ALL errors, then throw. The `@Transactional` rollback undoes all writes atomically. Caller gets a complete error report.

## Optimistic Locking with Retry

### Broken: @Version Without Retry

```kotlin
@Entity
class StockLevel(
    @Id @GeneratedValue val id: Long = 0,
    var availableQuantity: Int = 0,
    @Version var version: Long = 0
)

@Service
class ReservationService(private val stockRepo: StockLevelRepository) {
    @Transactional
    fun reserve(variantId: Long, quantity: Int) {
        val stock = stockRepo.findByVariantId(variantId)!!
        stock.availableQuantity -= quantity
        stockRepo.save(stock)
        // BUG: concurrent callers get OptimisticLockingFailureException with no retry!
    }
}
```

### Correct: @Retryable for Automatic Retry

```kotlin
@Configuration
@EnableRetry  // Required! Enables @Retryable proxy
class RetryConfig

@Service
class ReservationService(private val stockRepo: StockLevelRepository) {
    @Transactional
    @Retryable(
        include = [OptimisticLockingFailureException::class],
        maxAttempts = 3,
        backoff = Backoff(delay = 50)
    )
    fun reserve(variantId: Long, quantity: Int) {
        val stock = stockRepo.findByVariantId(variantId)!!
        if (stock.availableQuantity < quantity) throw InsufficientStockException(...)
        stock.availableQuantity -= quantity
        stockRepo.save(stock)
    }
}
// Requires: implementation("org.springframework.retry:spring-retry")
```

**Rule:** `@Version` alone prevents corruption but causes valid requests to fail under contention. Always pair with retry logic. Add `@EnableRetry` on a `@Configuration` class.

## Guardrails

- Do not put `@Transactional` on every service method by default.
- Do not hold database transactions open during external HTTP calls.
- Do not catch exceptions inside transactions and convert them to success-like flows.
- Do not publish irreversible side effects before commit.
- Do not assume retries are safe without idempotency.
