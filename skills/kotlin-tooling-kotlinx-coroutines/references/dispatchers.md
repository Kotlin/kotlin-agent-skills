# Dispatchers

## Main/UI Context

`Dispatchers.Main`, `viewModelScope`, and `lifecycleScope` are appropriate for updating UI state, handling lifecycle events, and calling main-safe suspend functions. They do not make every operation safe to run on the UI thread.

Blocking I/O or CPU-heavy work must either:

- switch context inside the coroutine body with `withContext(ioDispatcher/defaultDispatcher)`, or
- start the coroutine with an appropriate dispatcher when the entire block belongs there.

## Dispatcher Choice

- UI state and UI-only APIs: `Dispatchers.Main` or `Dispatchers.Main.immediate`.
- Blocking I/O: `Dispatchers.IO`, such as blocking file access, blocking SDK calls, or blocking database APIs.
- CPU-heavy work: `Dispatchers.Default`, such as parsing large payloads, sorting large lists, compression, or expensive recalculation.
- Production code should avoid `Dispatchers.Unconfined` unless the reason is explicit and narrow.

```kotlin
scope.launch {
    val data = withContext(ioDispatcher) {
        api.blockingLoad()
    }
    state.value = UiState.Content(data)
}
```

## Main-Safe Suspend Functions

`suspend` does not automatically switch threads. If a suspend function performs blocking work internally, callers from Main will still block the UI.

Repository and data-source suspend functions should be main-safe by switching to the appropriate dispatcher internally.

```kotlin
class ConfigRepository(
    private val ioDispatcher: CoroutineDispatcher
) {
    suspend fun readConfig(): Config = withContext(ioDispatcher) {
        file.readText().decodeConfig()
    }
}
```

## Inject Dispatchers

Hardcoded `Dispatchers.IO`, `Dispatchers.Default`, or `Dispatchers.Main` make tests harder to control. Prefer constructor parameters with defaults when the class performs dispatcher-sensitive work.

Recommended defaults:

- Repositories and data sources receive an `ioDispatcher`.
- CPU-heavy classes receive a `defaultDispatcher`.
- JVM tests that touch Main replace Main with `Dispatchers.setMain(testDispatcher)`.
