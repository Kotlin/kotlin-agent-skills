---
name: kotlin-backend-schema-migration
description: >
  Plan safe database schema evolution for Kotlin + Spring systems using
  Flyway or Liquibase. Covers the expand-contract pattern for column renames,
  dual-write entity mapping, zero-downtime migration phases, and common DDL
  traps. Use when changing tables, columns, or constraints in systems with
  live traffic, rolling deploys, or backward-compatibility requirements
  between old and new application versions.
license: Apache-2.0
metadata:
  author: JetBrains
  version: "1.0.0"
---

# Schema Migration for Kotlin

Column renames are the most common source of deployment failures. A direct `RENAME COLUMN`
destroys the old column, breaking any service version still reading it. The expand-contract
pattern keeps both columns alive during the transition.

This skill teaches safe schema evolution in Kotlin + Spring projects.

## Core Migration Rules

- Add before remove.
- Make old code tolerate new schema before making new code require it.
- Backfill separately from latency-sensitive request paths.
- Keep migration scripts deterministic and rerunnable per the tool's expectations.
- Never use `RENAME COLUMN` directly — it's an expand-copy-switch-drop plan in disguise.

## Column Rename: Expand-Contract Pattern

### Phase 1 — Expand

Add the new column alongside the old one. Copy existing data:

```sql
-- V2 migration: add new column, preserve old
ALTER TABLE orders ADD COLUMN delivery_address VARCHAR(255);
UPDATE orders SET delivery_address = shipping_address WHERE delivery_address IS NULL;
ALTER TABLE orders ALTER COLUMN delivery_address SET NOT NULL;
```

### Phase 2 — Dual-Write

Update the JPA entity to map **both** columns. Every write populates both so old-version
code reading the old column still sees correct data:

```kotlin
@Entity
@Table(name = "orders")
class Order(
    // New canonical column
    @Column(name = "delivery_address", nullable = false)
    var deliveryAddress: String,

    // Legacy column kept in sync for backward compatibility
    @Column(name = "shipping_address")
    var shippingAddress: String = deliveryAddress
) {
    @PrePersist @PreUpdate
    fun syncLegacyColumns() {
        shippingAddress = deliveryAddress
    }
}
```

Native queries referencing the old column name keep working throughout this phase.

### Phase 3 — Contract (Later Release)

Drop the old column **only** after proving no readers, writers, reports, or warehouse
queries still depend on it.

## Planning Workflow

1. Identify whether the change is additive, destructive, semantic, or data-moving.
2. Determine whether old and new application versions must coexist.
3. Plan the rollout in phases: expand → dual-write → backfill → switch reads → contract.
4. Decide whether rollback is realistic or roll-forward is safer.
5. Define smoke checks and validation queries around the migration.

## Common Migration Traps

- Adding a non-null column with a default may rewrite or lock a large table depending on database version.
- Unique constraints and index builds can be more disruptive than column adds.
- Backfills can saturate replicas and CDC consumers even when primary latency looks fine.
- Rolling deploys mean old and new code may both write. Dual-write compatibility must be explicit.
- `NOT NULL` enforcement often needs staged approach: detect violations, clean data, then enforce.
- Online index creation and lock behavior are vendor-specific. Plan by dialect.
- Never rewrite applied Flyway/Liquibase migrations — checksum validation will fail.

## Common Mistakes

- Using `ALTER COLUMN ... RENAME TO` — old code breaks immediately.
- Forgetting to dual-write: new code updates only the new column, old code reads stale data.
- Dropping the old column in the same release as the rename.
- Using H2 `MODE=PostgreSQL` in tests — H2 rename behavior differs from real PostgreSQL.

## Guardrails

- Do not recommend direct destructive DDL on live systems without a phased plan.
- Do not assume rollback is safe once data has been transformed.
- Do not couple request latency to large backfills.
- Do not edit historical applied migrations.
