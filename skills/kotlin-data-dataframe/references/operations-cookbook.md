# Operations cookbook

Comprehensive reference of common DataFrame operations. All examples assume the **compiler plugin is enabled** unless noted. For each, the String-API equivalent is shown when it differs meaningfully.

Read this when SKILL.md's operations section doesn't cover what you need.

## Table of contents

- [Selection](#selection)
- [Filtering](#filtering)
- [Sorting](#sorting)
- [Adding and updating columns](#adding-and-updating-columns)
- [Renaming](#renaming)
- [Type conversion](#type-conversion)
- [Removing](#removing)
- [Grouping and aggregation](#grouping-and-aggregation)
- [Reshaping: pivot, gather, split, implode, explode](#reshaping)
- [Joining](#joining)
- [Working with column groups and frame columns](#working-with-column-groups-and-frame-columns)
- [Row-level navigation](#row-level-navigation)
- [Statistical helpers](#statistical-helpers)
- [Sampling and slicing](#sampling-and-slicing)
- [Missing values](#missing-values)

## Selection

```kotlin
df.select { name and age }                       // by extension property
df.select { "name" and "age" }                   // by string
df.select { cols("name", "age") }                // by string, explicit
df.select { col("name") }                        // single
df.select { all() }                              // everything
df.select { all().except { internalId } }        // by exclusion
df.select { colsOf<String>() }                   // by Kotlin type
df.select { valueCols() }                        // exclude column groups
df.select { colGroups() }                        // only column groups
df.select { allBefore { age } }                  // positional
df.select { allAfter { age } }
df.select { colsAtAnyDepth() }                   // includes nested
df.select { all().filter { it.name().startsWith("user_") } }
```

Index-style access:

```kotlin
df["name"]                  // single column
df["name", "age"]           // multiple columns -> DataFrame
df.getColumnGroup("address")["city"]
```

## Filtering

```kotlin
df.filter { age > 18 }
df.filter { age in 18..65 && city != null }
df.filterBy { isActive }                          // boolean column shorthand
df.drop { age < 18 }                              // filter's complement
df.distinct()                                     // by all columns
df.distinct { name and email }                    // by selected columns
df.distinctBy { name and email }                  // keeps first of each group
```

## Sorting

```kotlin
df.sortBy { age }
df.sortByDesc { age }
df.sortBy { age and name }                        // multi-key, all ascending
df.sortBy { age.desc() and name }                 // mixed direction
df.sortBy { age.nullsLast() }                     // null handling
df.shuffle()                                      // random order
df.shuffle(seed = 42L)
df.reverse()
```

## Adding and updating columns

```kotlin
// Add a single computed column
df.add("isAdult") { age >= 18 }

// Add multiple at once
df.add {
    "isAdult" from { age >= 18 }
    "category" from { if (age < 18) "minor" else "adult" }
}

// Reference previously-added columns in the same block
df.add {
    "tax" from { price * 0.21 }
    "total" from { price + "tax"<Double>() }
}

// Insert at a specific position
df.insert("idx") { index() }.under("metadata")

// Update existing values
df.update { age }.with { it + 1 }                 // unconditional
df.update { age }.where { age < 0 }.with { 0 }    // conditional
df.update { age }.at(5).with { 99 }               // by row index
df.update { age }.at(2, 5, 7).with { -1 }         // multiple rows
df.update { name }.notNull().with { it.uppercase() }
df.update { age }.perRowCol { row, col -> col[row] ?: 0 }
df.fillNulls { age }.with { 0 }
df.fillNA { age }.with { 0 }                    // handles NaN and null
```

`update` returns a new DataFrame — DataFrame is immutable.

## Renaming

```kotlin
df.rename { age }.into("years")
df.rename { age and city }.into("years", "town")
df.rename("age" to "years", "city" to "town")     // by pair
df.rename { all() }.into { it.name().uppercase() } // by transform
df.renameToCamelCase()                            // snake_case → camelCase
df.renameToSnakeCase()
```

## Type conversion

```kotlin
df.convert { age }.to<Long>()                     // primitive
df.convert { price }.to<BigDecimal>()
df.convert { "amount" }.to<Double>()
df.convert { dateStr }.toLocalDate("yyyy-MM-dd") // requires @OptIn(FormatStringsInDatetimeFormats::class)
df.convert { dateStr }.toLocalDateTime("yyyy-MM-dd HH:mm:ss") // requires @OptIn(FormatStringsInDatetimeFormats::class)
df.convert { categoryStr }.to<Category>()         // String → enum
df.convert { json }.with { Json.decodeFromString<MyType>(it) }
df.parse()                                        // auto-parse all String columns
df.parse { "date" and "amount" }                  // parse selected
```

## Removing

```kotlin
df.remove { age }
df.remove { age and city }
df.remove { colsOf<String>() }
df.dropNulls { age }                              // drop rows where age is null
df.dropNulls()                                    // drop rows with ANY null
df.dropNA { age }                                 // also drops NaN
```

## Grouping and aggregation

```kotlin
// Stat shorthand: returns DataFrame<key, stat>
df.groupBy { city }.mean { age }
df.groupBy { city }.sum { revenue }
df.groupBy { city }.count()
df.groupBy { city }.max { age }
df.groupBy { city }.first()                       // first row per group
df.groupBy { city }.last()

// Custom aggregate
df.groupBy { city }.aggregate {
    mean { age }              into "avgAge"
    sum { revenue }           into "totalRevenue"
    count()                   into "rowCount"
    maxBy { age }.name        into "oldestPerson"
}

// pivot inside aggregate is allowed:
df.groupBy { city }.aggregate {
    pivot { gender }.count() into "byGender"
}

// concat groups back to flat DataFrame
df.groupBy { city }.concat()                       // re-flattens, no-op effectively
df.groupBy { city }.into("rows")                   // group rows into a FrameColumn
```

## Reshaping

```kotlin
// pivot — turn unique values of one column into new columns
df.pivot { month }.groupBy { product }.values { sales }
df.pivot { month }.values { sales }                       // no row grouping
df.pivot { month }.groupBy { product }.count()            // pivot table of counts

// gather — inverse of pivot
df.gather { jan and feb and mar }.into("month", "sales")
df.gather { colsOf<Int>() }.into("category", "value")

// split — break a String/List column into multiple columns
df.split { name }.by(" ").into("first", "last")
df.split { tags }.by(",").intoRows()                       // long-format
df.split { coordinates }.by(",").default(0).into("x", "y")

// implode — collect values across rows into a List per group
df.groupBy { category }.implode { name }                   // values → List<String>
df.implode { tags }                                         // collapse to single row

// explode — opposite of implode (one row per element)
df.explode { tags }
df.explode { events }                                       // for FrameColumn
```

## Joining

```kotlin
df1.innerJoin(df2) { id }                       // join on matching column name
df1.leftJoin(df2) { id }
df1.rightJoin(df2) { id }
df1.fullJoin(df2) { id }

// Multi-column join
df1.innerJoin(df2) { firstName and lastName }

// Different names on each side (use 'match' / 'right')
df1.innerJoin(df2) { id match right.userId }

// Filter (semi/anti) joins
df1.filterJoin(df2) { id }                       // keep rows in df1 that match
df1.excludeJoin(df2) { id }                       // keep rows in df1 that don't match

// Cross join
df1.crossJoin(df2)
```

## Working with column groups and frame columns

A `ColumnGroup` is a sub-DataFrame as a column (every cell has the same nested schema). A `FrameColumn` is a column whose cells are independent DataFrames (variable schema per row, like nested JSON arrays).

```kotlin
// Navigate into a group
df.select { person.firstName }
df.select { person { firstName and lastName } }    // multiple from a group

// Build a group from flat columns
df.group { firstName and lastName }.into("name")

// Flatten a group back to flat columns
df.ungroup { name }

// Move a column into a group
df.move { age }.into("person")

// Work with FrameColumn cells
df.add("eventCount") { events.rowsCount() }        // cells are DataFrames
df.explode { events }                              // expand to one row per inner row

// flatten everything — collapse all groups
df.flatten()
```

## Row-level navigation

Inside `add { ... }`, `update { ... }`, `filter { ... }` lambdas, `this` is `DataRow<T>`:

```kotlin
df.add("prevAge") { prev()?.age }                  // previous row, null at index 0
df.add("nextAge") { next()?.age }                  // next row, null at last index
df.add("rowIdx")  { index() }                      // current row index
df.add("relative") { age - df.mean { age } }       // refer to whole DataFrame
df.add("diff") { age - (prev()?.age ?: age) }
df.add("rowDf") { it }                             // capture the DataRow itself
```

## Statistical helpers

These can be called on a whole DataFrame, a single column, or inside an aggregate:

```kotlin
df.mean { age }
df.median { age }
df.std { age }
df.min { age }
df.max { age }
df.sum { revenue }
df.count()
df.count { age > 18 }                             // with predicate

df.describe()                                       // summary stats DataFrame
df.describe { age and salary }                      // only selected columns
```

## Sampling and slicing

```kotlin
df.head(10)                                         // first 10 rows
df.tail(10)                                         // last 10 rows
df.take(5)                                          // alias for head
df.drop(5)                                          // skip first 5

df[0..9]                                            // index range
df[listOf(0, 2, 5)]                                 // arbitrary indices

df.sample(100)                                      // 100 random rows
df.sample(0.1)                                      // 10% sample
df.sampleFraction(0.1, seed = 42L)
```

## Missing values

DataFrame distinguishes:
- **null** — Kotlin's nullability (column type is `T?`)
- **NA** — null or `Double.NaN` / `Float.NaN`

```kotlin
df.dropNulls()                                      // drop rows with any null
df.dropNulls { age }                                // only check age
df.dropNA { age }                                   // also treat NaN as missing

df.fillNulls { age }.with { 0 }
df.fillNA { age }.with { 0.0 }
df.fillNulls { colsOf<Int>() }.with { 0 }
```

## I/O extras not in SKILL.md

```kotlin
// CSV options
DataFrame.readCsv("data.csv", delimiter = ';', header = listOf("a", "b"))
DataFrame.readCsv("data.csv", colTypes = mapOf("age" to ColType.Int))
df.writeCsv("out.csv", delimiter = '\t')

// JSON nested handling — produces ColumnGroup / FrameColumn naturally
DataFrame.readJson("data.json")                     // arrays → FrameColumn

// SQL — see dataframe-jdbc module
DataFrame.readSqlTable(connection, "users", limit = 1000)
DataFrame.readSqlQuery(connection, "SELECT id, name FROM users WHERE active = true")

// Arrow / Parquet — see dataframe-arrow module
DataFrame.readArrowFeather("data.arrow")
df.writeArrowFeather("out.arrow")
```

## Tips for chained pipelines

1. Keep the pipeline as one expression when you want the plugin's schema flow.
2. If you must break for readability, use `convertTo<Schema>()` at each break point.
3. Use `.also { it.schema().print() }` or `.also { it.print() }` mid-chain when debugging — it's a no-op on data.
4. Inside the IDE, you can hover over each function call with an adjusted return type, and the info warning will tell you about the schema.
5. For very long pipelines, define `@DataSchema` interfaces for each major stage; they document intent and let you split the chain safely.
