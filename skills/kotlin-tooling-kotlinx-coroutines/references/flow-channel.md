# Flow And Channel

## Blocking Calls In `flow`

`flow {}` does not automatically switch threads. Blocking calls inside `flow {}` block the collector's context.

```kotlin
fun observeData(): Flow<Data> = flow {
    emit(blockingLoad())
}.flowOn(ioDispatcher)
```

Alternatively, keep the blocking part in a main-safe suspend function that switches context internally.

## Cold And Hot Streams

- `Flow`: cold stream. Each collector re-runs upstream work. Good for one-shot requests, queries, and transformation pipelines.
- `StateFlow`: hot stream with a current value. Good for observable state.
- `SharedFlow`: hot shared emission stream. Good for events or shared emissions when replay and buffering are intentionally configured.

Use `stateIn` for state sharing and `shareIn` for sharing upstream work. For UI state, prefer `SharingStarted.WhileSubscribed(...)` unless the application intentionally needs eager background work.

## `collect` And `collectLatest`

Use `collect` when every item must be processed completely.

Use `collectLatest` only when processing the previous item should be cancelled when a newer item arrives, such as search input or rendering only the latest state.

Do not use `collectLatest` for work that must not be lost, such as database writes, uploads, or analytics events.

## Lifecycle-Aware Collection

On Android, collecting with a plain `launch { flow.collect { ... } }` can keep collecting while UI is not visible.

Rules:

- In Fragments, use `viewLifecycleOwner.lifecycleScope`.
- Use `repeatOnLifecycle(Lifecycle.State.STARTED)` or `flowWithLifecycle` for UI collection.
- In Compose, prefer lifecycle-aware state collection such as `collectAsStateWithLifecycle()` when available.

```kotlin
viewLifecycleOwner.lifecycleScope.launch {
    viewLifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
        viewModel.uiState.collect(::render)
    }
}
```

## `SharedFlow` Configuration

Configure event streams intentionally:

```kotlin
private val _events = MutableSharedFlow<UiEvent>(
    replay = 0,
    extraBufferCapacity = 1,
    onBufferOverflow = BufferOverflow.DROP_OLDEST
)
```

If consumers need the latest state, use `StateFlow` instead of `SharedFlow`.

## Channel Ownership

Manual `Channel` creation must define an owner and close policy. Otherwise consumers can suspend forever or resources can leak.

- Prefer `produce {}` for a single producer when a `ReceiveChannel` is appropriate.
- Prefer `callbackFlow` for callback-to-Flow bridges, with listener cleanup in `awaitClose`.
- Do not share `consumeEach` across multiple consumers.
- Prefer `SharedFlow` for broadcast-style data.

```kotlin
fun eventsFromSdk(sdk: Sdk): Flow<Event> = callbackFlow {
    val listener = object : SdkListener {
        override fun onEvent(event: Event) {
            trySend(event)
        }
    }

    sdk.addListener(listener)
    awaitClose { sdk.removeListener(listener) }
}
```
