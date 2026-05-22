---
name: kotlin-data-dataframe
description: >
Use for Kotlin DataFrame (`kotlinx.dataframe`) tasks — reading,
transforming, or analyzing tabular data in Kotlin. Trigger on mentions
of `DataFrame`, `dataFrameOf`, `readCsv`/`readJson`/`readExcel`,
`@DataSchema`, extension-property column accessors like `df.columnName`,
or "unresolved reference" errors on DataFrame columns.
license: Apache-2.0
metadata:
author: JetBrains
version: "1.0.0"
---
# Kotlin DataFrame
A skill for using **kotlinx.dataframe**, the JetBrains-maintained type-safe tabular data library for Kotlin.
## The three contexts
The same DataFrame operation can be written in three different styles depending on context; pick the right one before you start writing.

| Context                                                              | Schema awareness                                      | Idiomatic syntax                                                                                     |
|----------------------------------------------------------------------|-------------------------------------------------------|------------------------------------------------------------------------------------------------------|
| **Kotlin Notebook** (Jupyter / Kotlin kernel)                        | Auto-generated **after each cell** runs               | `df.columnName` works once the cell that creates `df` has run                                        |
| **Project + compiler plugin** (Gradle: `kotlin("plugin.dataframe")`) | Inferred **at compile time** through operation chains | `df.columnName` works inline; schema updates flow through chains but not across variable assignments |
| **Project / plain Kotlin without plugin**                            | None — String API only                                | `df["columnName"]` and `it["columnName"]` everywhere; type casts required                            |

Before writing code, **determine which context the user is in**. If unclear, ask. Wrong context = code that won't compile or won't be idiomatic. Look for:
- `.ipynb` files or `%use dataframe` → notebook
- `kotlin("plugin.dataframe")` in `build.gradle.kts` → plugin
- Just `implementation("org.jetbrains.kotlinx:dataframe:...")` with no plugin → String API

## The compiler plugin — what's different from "normal" Kotlin
DataFrame can have the `kotlin("plugin.dataframe")` compiler plugin enabled in any project. It does **static interpretation of DataFrame operations at compile time**, generating extension properties for each schema state in your chain.
### What the plugin generates
After every chained operation whose schema effect is compile-time-determinable, the plugin synthesizes a fresh anonymous schema marker (e.g. `DataFrameOf_39`) plus extension properties on `DataRow<that schema>` and a columns-scope for the DSL. This means **the next operation in the chain sees the columns produced by the previous operation as typed extension properties.**
Concrete example with plugin enabled:
```kotlin
val df = dataFrameOf("name", "age")(
    "Alice", 30,
    "Bob", 17,
)
df
    .add("isAdult") { age >= 18 }            // 'age' resolved from inferred schema
    .filter { isAdult }                       // 'isAdult' just added — already typed
    .rename { name }.into("fullName")
    .sortByDesc { fullName }                  // 'fullName' usable immediately
```
Same code **without** the plugin (or after assigning to a variable mid-chain):
```kotlin
df
    .add("isAdult") { "age"<Int>() >= 18 }     // need explicit type
    .filter { "isAdult"<Boolean>() }
    .rename("name").into("fullName")
    .sortByDesc { "fullName"<String>() }
```
### What the plugin does NOT analyze
These operations depend on runtime data and cannot have their result schemas inferred by the plugin. The plugin leaves them with an empty schema; you must either provide a `@DataSchema` to `convertTo<>()` or fall back to the String API afterwards:
- `read*` family (`readCsv`, `readJson`, `readExcel`, `readSqlTable`) — schema lives in the file
- `pivot` — output columns depend on data values
- `parse` — output types depend on data values (will turn String-columns into `DataColumn<Any>`)
- `split` — works for a handful of cases, like when exact new names are provided, not when defining the new names
  programmatically
- Some `filter` overloads in special scopes
### Setup recipe (Gradle + plugin)
```kotlin
// build.gradle.kts
plugins {
    kotlin("jvm") version "2.3.20"
    kotlin("plugin.dataframe") version "2.3.20"   // must match Kotlin version, use newest Kotlin version available
}

dependencies {
    implementation("org.jetbrains.kotlinx:dataframe:1.0.0")  // check latest
}
```
```properties
# gradle.properties — REQUIRED, see KT-66735
kotlin.incremental=false
```
Without `kotlin.incremental=false`, the plugin's generated schemas can go stale between builds and you'll get "unresolved reference: columnName" errors that disappear after a clean build. **Always include this line.**This is likely solved in Kotlin 2.4+.
IDE support for inline schema hovers and completion requires IntelliJ IDEA 2025.2+ with Kotlin 2.2.20+.
### Setup recipe (Notebook)
```kotlin
%useLatestDescriptors
%use dataframe
```
That's it — no plugin, no `@DataSchema`. After any cell that declares or assigns a DataFrame, the kernel generates extension properties live. Reference the DataFrame from a later cell to use `df.columnName`.
### Setup recipe (Gradle without plugin)
Same dependency, no plugin. You're restricted to the String API: `df["col"]`, `it["col"] as Int`, etc.
## `@DataSchema` — declaring schemas explicitly
When data comes from a file (CSV, JSON, SQL), the plugin can't read it at compile time. Declare the expected shape with `@DataSchema` and use `convertTo<>()` or `cast<>()` to thread it through:
```kotlin
@DataSchema
data class Repo(
    val fullName: String,
    val stargazersCount: Int,
    val topics: String,
)

val df = DataFrame.readCsv("repos.csv")
    .convertTo<Repo>() // now typed as DataFrame<Repo>
    .filter { stargazersCount > 50 } // typed access from here on
```
`@DataSchema` works on both `data class` and `interface`. Interfaces are preferred when the schema describes data you only read (not construct).
### `@ColumnName` for non-Kotlin-identifier names
When the actual column name in the CSV/JSON isn't a valid Kotlin identifier (or uses snake_case while you want camelCase):
```kotlin
@DataSchema
data class Row(
    @ColumnName("first_name") val firstName: String,
    @ColumnName("user-id") val userId: Int,
)
```
### Generating a schema from existing data
Create a separate file with `main()` function: run `df.generateDataClasses()` (or `df.generateInterfaces()`), `.print()` and copy the output into your project. Alternatively, in a notebook: run `df.generateDataClasses()` (or `df.generateInterfaces()`) and copy the output into your Gradle project.
## Construction
`dataFrameOf("name" to columnOf(...), ...)` is the recommended way to define a dataframe, but there are a few alternatives:

```kotlin
// 0. Map-style, accepts either lists or columns as values.
val df = dataFrameOf(
    "name" to listOf("Alice", "Bob", "Charlie"),
    "age" to listOf(15, 20, 100),
)
// name is a column group
val df = dataFrameOf(
    "name" to columnOf(
        "firstName" to columnOf("Alice", "Bob", "Charlie"),
        "lastName" to columnOf("Cooper", "Dylan", "Daniels"),
    ),
    "age" to columnOf(15, 20, 100),
)

// 1. vararg of values, count must be divisible by column count
val df = dataFrameOf("name", "age")(
    "Alice", 30,
    "Bob", 17,
)

// 2. By declared columns
val name by columnOf("Alice", "Bob")
val age by columnOf(30, 17)
val df = dataFrameOf(name, age)

// 3. From a list of POJOs (uses reflection on properties)
data class Person(val name: String, val age: Int)
val df = listOf(Person("Alice", 30)).toDataFrame()

// 4. From Map
val df = mapOf("name" to listOf("Alice", "Bob"), "age" to listOf(30, 17)).toDataFrame()
```

`columnOf(1, 2, null)` infers `Int?`. Type inference looks at the actual runtime values.
## Common operations (with-plugin idiomatic syntax)

```kotlin
// Selection
df.select { name and age } // by extension property
df.select { cols("name", "age") } // by string
df.select { colsOf<String>() } // by type
// Filtering
df.filter { age > 18 }
df.filter { city != null && country == "NL" }
// Sorting
df.sortBy { age }
df.sortByDesc { age }
df.sortBy { city and age } / multi-key
// Add a column (lambda receives DataRow<schema>)
df.add("isAdult") { age >= 18 }
df.add("nextAge") { next()?.age ?: age } // next/prev navigate rows
// Update existing values
df.update { age }.where { age < 0 }.with { 0 }
df.update { age }.at(5).with { 99 }
// Rename
df.rename { age }.into("years")
df.renameToCamelCase()
// Convert types
df.convert { "amount" }.to<Double>()
@OptIn(FormatStringsInDatetimeFormats::class)
df.convert { dateStr }.toLocalDate("yyyy-MM-dd")
// Drop columns
df.remove { age }
df.select { all().except { age } } // by exclusion (compiler plugin support for `except` likely requires Kotlin 2.5+)
// Group + aggregate
df.groupBy { city }.mean { age }
df.groupBy { city }.aggregate {
    mean { age } into "avgAge"
    count() into "count"
}
// Pivot (schema becomes data-dependent — falls back to String API after)
df.pivot { month }.groupBy { product }.values { sales }
// Joins
df1.innerJoin(df2) { id }
df1.leftJoin(df2) { df1.id match right.userId }
```
For the full operations list, see `references/operations-cookbook.md`.
## Reading and writing data
DataFrame's IO is split into modules. The main `dataframe` artifact pulls them in transitively, but if you depend only on `dataframe-core`, add format modules explicitly.
```kotlin
// CSV/TSV (dataframe-csv) (+ dataframe-json if your CSV contains JSON to parse)
DataFrame.readCsv("data.csv")
DataFrame.readTsv(URL("https://example.com/data.csv"))
df.writeCsv("out.csv")
// JSON (dataframe-json)
DataFrame.readJson("data.json")
DataFrame.readJsonStr("""[{"a":1}]""")
df.writeJson("out.json")
// Excel (dataframe-excel)
DataFrame.readExcel("data.xlsx", sheetName = "Sheet1")
df.writeExcel("out.xlsx")
// SQL (dataframe-jdbc)
DataFrame.readSqlTable(connection, "users")
DataFrame.readSqlQuery(connection, "SELECT * FROM users WHERE age > 18")
// Arrow (dataframe-arrow)
DataFrame.readArrowFeather(file) // and similar for IPC, Parquet (which takes vararg arguments)
DataFrame.readArrow(arrowReader)
df.writeArrowIPC(file)
df.writeArrowFeather(file)

```
In a notebook, the corresponding `%use` integrations are included automatically. In Gradle, all the above ship under`org.jetbrains.kotlinx:dataframe`; only when you slim down to `dataframe-core` do you need to add format-specific modules.
## Hierarchical / nested data
`DataFrame` supports `ColumnGroup` (a sub-DataFrame as a column) and `FrameColumn` (a column whose cells are themselves DataFrames). JSON with nested objects/arrays naturally produces these. `FrameColumn`s cannot contain nulls. A`ValueColumn<DataFrame<>?>` is possible though.
```kotlin
// Navigate into a group
df.select { person.firstName and person.lastName }
// Group flat columns into a sub-structure
df.group { firstName and lastName }.into("name")
// Flatten a group
df.ungroup { name }
// Explode a FrameColumn (one row per inner row)
df.explode { events }
```
## Output and rendering
In notebooks, the last expression in a cell renders as an interactive table automatically. To produce HTML in a Gradle project:
```kotlin
df.toHtml().writeHtml(File("report.html"))
```
To print to console:
```kotlin
df.print()                  // simple text table
df.schema().print()         // just the schema
```
## Critical gotchas

1. **Operations on a `val` don't update that `val`.** DataFrame is immutable: `df.add("b") {...}` returns a *new* DataFrame, leaving the original unchanged. If a column accessor is missing where you expect it, the user likely split a chain mid-way; either keep the chain together, or declare a `@DataSchema` for the intermediate variable so its type carries the new columns. Don't try to pattern-match against pandas here — there is no in-place mutation, no `inplace=True`, no chained assignment.
```kotlin
val df1 = dataFrameOf("a")(1, 2, 3)
df1.a // OK — df1 has column 'a'
val df2 = df1.add("b") { a * 2 }
df2.a // OK — df2 is a brand new DataFrame with 'a' and 'b'
df2.b // OK
df1.b // ERROR — df1 was never modified; only df2 has 'b'
```
2.**Plugin can't read files at compile time.** The old KSP-based `@ImportDataSchema` is gone in DataFrame 1.0.0-Beta5+. Use one of: declare `@DataSchema` manually, generate it once in a notebook/function with `df.generateCode()`, or just use the String API after `readCsv`.
3.**Pivot/gather/parse return runtime schemas.** After these, the plugin's accessors are gone; either `convertTo<>()` or `cast<>()` into a declared schema or use String access.
4.**DslMarker-receiver lambdas break extension properties.** Inside a `@DslMarker`-receiver lambda (notably Compose builders like `Column { }`), DataFrame's generated extension properties don't resolve. Construct/transform the DataFrame outside the lambda and only consume it inside.
5.**`df.print()` ≠ display.** In Gradle, `df.print()` writes a plain text table to stdout; the rich HTML rendering is notebook-only unless you explicitly call `df.toHtml()`.
## When to fall back to the String API
The String API (`df["name"]`, `it["name"]`, with casts) is always available. Use it when:
- The user is on a plain Kotlin project without the plugin.
- A column name is dynamic (known only at runtime).
- After a `pivot`/`gather`/`parse` step where the plugin can't infer the new schema.
- Inside a `@DslMarker`-receiver lambda where extension properties don't resolve.
Mixing both styles in one program is fine and common.
## Where to look for more
- Library home: <https://kotlin.github.io/dataframe/home.html>
- Quickstart: <https://kotlin.github.io/dataframe/quickstart.html>
- Compiler plugin: <https://kotlin.github.io/dataframe/compiler-plugin.html>
- Extension properties: <https://kotlin.github.io/dataframe/extensionpropertiesapi.html>
- Schemas: <https://kotlin.github.io/dataframe/schemas.html>
- Operations reference: <https://kotlin.github.io/dataframe/operations.html>
- Reading data: <https://kotlin.github.io/dataframe/read.html>
- SQL: <https://kotlin.github.io/dataframe/readSqlDatabases.html>
- Notebook setup: <https://kotlin.github.io/dataframe/setupkotlinnotebook.html>
- Gradle setup: <https://kotlin.github.io/dataframe/setupgradle.html>
- Source: <https://github.com/Kotlin/dataframe>