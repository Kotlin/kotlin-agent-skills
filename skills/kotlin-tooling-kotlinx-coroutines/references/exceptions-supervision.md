# Exceptions And Supervision

## `Job` Vs `SupervisorJob`

A regular `Job` has these semantics:

- A child failure propagates upward.
- Parent cancellation propagates downward to all children.
- A failing child usually cancels its sibling tasks.

This is appropriate for strongly coupled work where the operation should succeed or fail as a whole.

`SupervisorJob` has different child-failure semantics:

- Parent cancellation still cancels all children.
- One child failure does not automatically cancel siblings.

This is appropriate for independent sections of work where one failed child should not invalidate the rest.

The decision is about business semantics, not which API is more advanced: are these child tasks one atomic operation, or independent units?

## `supervisorScope` Vs `SupervisorJob`

- `SupervisorJob`: defines supervision for a scope. The scope must have a clear lifecycle owner.
- `supervisorScope`: applies supervision temporarily inside a structured block.

```kotlin
suspend fun loadIndependentSections() = supervisorScope {
    launch { loadBanner() }
    launch { loadFeed() }
}
```

Do not pass `SupervisorJob()` directly to a single builder such as `launch(SupervisorJob()) { ... }`. That often fails to provide the expected supervision and may disconnect the coroutine from its parent.

## `CoroutineExceptionHandler` And `async`

`CoroutineExceptionHandler` handles uncaught coroutine exceptions. Exceptions from `async` are stored inside the `Deferred` and normally surface at `await()`.

- Use a handler at a top-level `launch` boundary to log uncaught failures.
- Always `await()` `async` results.
- Handle `async` errors at the await site.
- Do not expect a handler to catch an unawaited `async` failure.

```kotlin
private val handler = CoroutineExceptionHandler { _, throwable ->
    logger.error(throwable)
}

fun refresh() {
    scope.launch(handler) {
        state.value = UiState.Content(repository.load())
    }
}
```

## Business Errors Are Not Cancellation

Do not subclass or throw `CancellationException` for domain failures. Use normal exceptions, a sealed result type, or a domain error model.
