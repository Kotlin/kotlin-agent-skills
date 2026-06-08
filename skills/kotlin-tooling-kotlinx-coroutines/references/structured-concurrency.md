# Structured Concurrency

## Scope Ownership

Do not use `GlobalScope` in production code. It is not owned by the caller, so callers cannot naturally cancel the work, wait for completion, or observe failures when a screen, request, or business operation ends.

Prefer:

- UI work: framework-owned scopes such as `viewModelScope`, `lifecycleScope`, or `rememberCoroutineScope`.
- Concurrent work inside suspend functions: `coroutineScope {}` or `supervisorScope {}`.
- Long-lived background work: an injected `CoroutineScope` with a documented owner and cancellation point.

```kotlin
suspend fun syncAll() = coroutineScope {
    launch { syncProfile() }
    launch { syncSettings() }
}
```

## `launch` And `async`

- Use `launch` for work that does not return a value.
- Use `async` only when the result is needed.
- Every `Deferred` must be awaited with `await()` or `awaitAll()`.
- An unawaited `async` loses the result and hides failure from the expected call site.

```kotlin
val page = coroutineScope {
    val main = async { loadMainData() }
    val extra = async { loadExtraData() }
    Page(main.await(), extra.await())
}
```

## `awaitAll` Failure Propagation

In `coroutineScope { ... awaitAll() }`, a failing child cancels the parent scope and usually cancels sibling tasks. This is correct when tasks are strongly dependent and the whole operation should fail together.

For independent sibling tasks, use `supervisorScope` and make each task produce an explicit `Result` or fallback value.

```kotlin
val results = supervisorScope {
    loaders.map { loader ->
        async { runCatchingCancellable { loader.load() } }
    }.awaitAll()
}
```

## Do Not Pass A Fresh Job To Builders

Avoid:

```kotlin
scope.launch(Job()) { work() }
scope.async(SupervisorJob()) { work() }
withContext(Job()) { work() }
```

Passing a fresh job replaces the parent job in the coroutine context and can break parent-child cancellation. Use `supervisorScope {}` for local supervision. Use `CoroutineScope(SupervisorJob() + dispatcher)` only when there is a real long-lived owner that will cancel it.

## `coroutineScope` Ending With `launch`

`suspend fun foo() = coroutineScope { launch { work() } }` looks like fire-and-forget, but `coroutineScope` waits for all children. If the work must continue after the caller returns, use a clearly owned external scope and explain why the work outlives the caller.

## Avoid `runBlocking` In Suspend Code

`runBlocking` blocks the current thread. Inside suspend functions or coroutine bodies, it defeats the non-blocking model and can cause UI freezes, thread starvation, or slow tests.

Use:

- normal suspend calls,
- `coroutineScope` for child concurrency,
- `runTest` in tests.
