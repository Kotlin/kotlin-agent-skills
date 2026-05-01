# Kotlin feature search hints

Load when `symbol-map.md` does not list the user's wording verbatim. Use
these grep/rg expressions to find capsules and status-index rows.

Run via `rg` (or `grep -nE` for the POSIX fallback):

```bash
rg -n "^### id:|explicit backing|context parameters|collection literals" references/*.md
grep -nE "^### id:|explicit backing|context parameters|collection literals" references/*.md
```

Structural anchors:

- status-index rows: `^\| .*kt[0-9][0-9]-`
- Capsule headings: `^### id:`
- Stub rows / pointers: `(stub →|Canonical capsule:)`

Conceptual aliases (catch what users actually type):

- Context features: `context parameters|context receivers|context-sensitive`
- Context overloads: `context.*overload|overload.*context`
- Name-based destructuring: `name-based destructuring|destructuring|only-syntax|complete`
- Backing fields: `explicit backing|backing fields`
- Collection / array literals: `collection literals|collection-literals|array literals`
- Annotation targets: `annotation target|@all|param-property`
- Warning policy: `warning-level|DIAGNOSTIC_NAME|Werror|nowarn`
- Time / UUID stdlib: `Uuid|UUID|Clock|Instant`
- Multiplatform / KMP: `multiplatform|MPP|KMP`
- K2 compiler / KSP: `K2 compiler|KSP|kotlin symbol processing`
- Value classes / inline classes: `value class|inline class|@JvmInline|jvm-expose-boxed`
- Compose: `compose compiler|@Composable|ProGuard mapping`
- Wasm: `wasmJs|wasmWasi|Kotlin/Wasm`
- Native / Apple: `Kotlin/Native|Apple|Swift export|cinterop`

For area-scoped lookups, append the area suffix to the capsule-headings
anchor — e.g., `^### id: .*stdlib`, `^### id: .*wasm`, `^### id: .*gradle`.
