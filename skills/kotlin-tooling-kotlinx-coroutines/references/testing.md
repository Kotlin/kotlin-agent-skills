# Coroutine Testing

## Use `runTest`

Coroutine unit tests should use `runTest`, not `runBlocking`. Avoid real `delay()` and `Thread.sleep()`. Advance virtual time instead.

```kotlin
@Test
fun testDelay() = runTest {
    val job = launch { delay(1_000) }
    advanceTimeBy(1_000)
    job.join()
}
```

Useful test APIs:

- `advanceTimeBy(...)`
- `runCurrent()`
- `advanceUntilIdle()`
- `StandardTestDispatcher`
- `UnconfinedTestDispatcher` for eager execution when appropriate

## Replace Main Dispatcher

Code that touches `Dispatchers.Main`, Android `viewModelScope`, or Main-confined state usually needs Main replacement in JVM tests.

```kotlin
private val testDispatcher = StandardTestDispatcher()

@Before
fun setUp() {
    Dispatchers.setMain(testDispatcher)
}

@After
fun tearDown() {
    Dispatchers.resetMain()
}
```

## Make Background Work Awaitable

Ownerless fire-and-forget work makes tests unreliable because the test cannot wait for completion or assert final state deterministically.

Rules:

- Inject scopes or dispatchers when production code starts background work.
- If ViewModel code uses `viewModelScope`, replace Main in tests and use `advanceUntilIdle()`.
- Avoid creating uncontrolled `CoroutineScope(...)` instances inside the class under test.

```kotlin
viewModel.load()
advanceUntilIdle()
assertEquals(expected, viewModel.uiState.value)
```

## Flow Tests

For Flow tests:

- Collect from `runTest`.
- Use virtual time for debounce, timeout, and retry behavior.
- If the project already uses Turbine, prefer it for multi-emission assertions.

```kotlin
repository.observeUsers().test {
    assertEquals(expectedUsers, awaitItem())
    cancelAndIgnoreRemainingEvents()
}
```
