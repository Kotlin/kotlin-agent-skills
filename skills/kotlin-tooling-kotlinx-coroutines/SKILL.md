---
name: kotlin-tooling-kotlinx-coroutines
description: >
  Use this skill when writing, reviewing, or refactoring Kotlin code that uses
  kotlinx.coroutines, structured concurrency, CoroutineScope ownership,
  launch/async, Dispatchers, cancellation, exception handling, supervision,
  Flow, StateFlow, SharedFlow, Channel, or kotlinx-coroutines-test. It helps
  produce lifecycle-aware, cancellation-safe, main-safe, and testable coroutine
  code for Kotlin, Android, backend, and multiplatform projects.
license: Apache-2.0
metadata:
  author: JetBrains
  version: "1.0.0"
---

# Kotlin Coroutines: Structured Concurrency

Use this skill to keep coroutine code structured, cancellation-safe, main-safe, and testable.

## Workflow

When this skill is active:

1. Identify the coroutine topic and risk first: scope ownership, dispatcher choice, cancellation, exception propagation, Flow collection, Channel ownership, or deterministic tests.
2. Load the relevant reference only when needed:
   - `references/structured-concurrency.md`: scope ownership, `launch`, `async`, `coroutineScope`, `supervisorScope`, and `runBlocking`.
   - `references/dispatchers.md`: dispatcher selection, main-safety, and dispatcher injection.
   - `references/cancellation.md`: cooperative cancellation, `CancellationException`, timeouts, cleanup, and polling.
   - `references/exceptions-supervision.md`: `Job`, `SupervisorJob`, `supervisorScope`, `CoroutineExceptionHandler`, and `async` failures.
   - `references/flow-channel.md`: Flow, StateFlow, SharedFlow, lifecycle-aware collection, Channel, and callback bridging.
   - `references/testing.md`: `runTest`, virtual time, test dispatchers, and replacing `Dispatchers.Main`.
3. For code review or refactoring, report:
   - the issue,
   - the unsafe or fragile pattern,
   - the corrected code,
   - the reasoning.
4. For conceptual questions, avoid unnecessary code unless a short example clarifies the decision.
5. Do not recommend production code that violates the hard rules below.
6. Prefer the project's existing architecture, dependency injection style, and test style.

## Quick Triage

| Symptom | Preferred response |
|---|---|
| `GlobalScope`, unclear lifecycle, or "where should I launch?" | Use a lifecycle-owned scope, an injected long-lived scope, or local structured concurrency. |
| `async` is used but the `Deferred` is never awaited | Use `launch`, or ensure every `Deferred` is awaited. |
| A suspend function launches work into an external scope | Keep work structured unless it intentionally outlives the caller. |
| `runBlocking` appears inside suspend/coroutine code | Replace with suspend calls, `coroutineScope`, or `runTest` in tests. |
| Blocking I/O runs on Main or Default | Move it to `withContext(ioDispatcher)`. |
| CPU-heavy work runs on Main or IO | Move it to `withContext(defaultDispatcher)`. |
| Production code hardcodes dispatchers in code that must be tested | Prefer injected `CoroutineDispatcher`s. |
| `Job()` or `SupervisorJob()` is passed directly to `launch`, `async`, or `withContext` | Use `coroutineScope`, `supervisorScope`, or a clearly owned `CoroutineScope`. |
| `catch (Exception)` wraps suspend calls | Re-throw `CancellationException`. |
| Polling or long-running loops | Use `while (isActive)` and cancellable suspension points. |
| `withTimeout` unexpectedly cancels parent work | Prefer `withTimeoutOrNull`, or explicitly catch `TimeoutCancellationException`. |
| `CoroutineExceptionHandler` is expected to catch `async` failures | Await the `Deferred`; `async` exceptions surface at `await()`. |
| Coroutine tests are slow or flaky | Use `runTest`, virtual time, and `TestDispatcher`. |
| UI collects Flow forever | Use lifecycle-aware collection APIs on Android. |
| `MutableSharedFlow` events are lost or backpressure is unclear | Configure `replay`, `extraBufferCapacity`, and `onBufferOverflow` intentionally. |

## Hard Rules

### Scope And Structured Concurrency

- Do not use `GlobalScope` in production code.
- UI work should use framework-owned scopes such as `viewModelScope`, `lifecycleScope`, or `rememberCoroutineScope` when those APIs are available.
- Use `coroutineScope {}` inside suspend functions when child work must complete or cancel with the caller.
- Use an injected external `CoroutineScope` only when work must outlive the caller; name the owner and cancellation point.
- Do not use `coroutineScope { launch { ... } }` as fire-and-forget. `coroutineScope` waits for its children.
- Do not pass a fresh `Job()` or `SupervisorJob()` directly to `launch`, `async`, or `withContext`.

```kotlin
// Unsafe: the caller cannot wait for completion, observe failure, or cancel the work.
suspend fun sync() {
    GlobalScope.launch { repository.sync() }
}

// Safe: the caller owns completion and cancellation.
suspend fun sync() = coroutineScope {
    launch { repository.sync() }
}
```

### `launch` And `async`

- Use `launch` for work that does not return a value.
- Use `async` only when the result is needed.
- Every `Deferred` must be awaited with `await()` or `awaitAll()`.
- Wrap parallel child work in `coroutineScope {}` or `supervisorScope {}`.

```kotlin
suspend fun loadDashboard(): Dashboard = coroutineScope {
    val profile = async { profileRepository.load() }
    val summary = async { summaryRepository.load() }

    Dashboard(
        profile = profile.await(),
        summary = summary.await()
    )
}
```

Use `supervisorScope` when sibling tasks are independent and one failure should not automatically cancel the rest.

```kotlin
suspend fun loadCards(): List<Result<Card>> = supervisorScope {
    cardLoaders
        .map { loader -> async { runCatchingCancellable { loader.load() } } }
        .awaitAll()
}
```

### Dispatchers And Main-Safety

- UI-only work uses `Dispatchers.Main` or `Dispatchers.Main.immediate`.
- Blocking I/O uses `Dispatchers.IO`.
- CPU-heavy work uses `Dispatchers.Default`.
- Avoid `Dispatchers.Unconfined` in production code unless the reason is explicit and narrow.
- A suspend function must be main-safe: callers should be able to call it from Main without blocking the UI.
- Prefer injected dispatchers for production classes that need deterministic tests.

```kotlin
class UserRepository(
    private val api: UserApi,
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO
) {
    suspend fun loadUser(id: String): User = withContext(ioDispatcher) {
        api.blockingLoadUser(id)
    }
}
```

### Cancellation

- Do not swallow `CancellationException`.
- Do not use `CancellationException` for business errors.
- In long CPU loops, call `yield()` or `ensureActive()`.
- Polling should use `while (isActive)` and cancellable delays.
- If cleanup in `finally` must call suspend APIs, wrap only that cleanup in `withContext(NonCancellable)`.
- Do not reuse a `CoroutineScope` after cancelling it.

```kotlin
try {
    repository.sync()
} catch (e: CancellationException) {
    throw e
} catch (e: Exception) {
    logger.error(e)
}
```

### Flow And Channel

- Keep `flow {}` non-blocking, or move blocking work with `flowOn(ioDispatcher)` or `withContext(ioDispatcher)`.
- Use `StateFlow` for observable state with a current value.
- Use `SharedFlow` for shared events or emissions, with explicit replay and buffer choices.
- Use lifecycle-aware collection APIs for Android UI collection.
- Manual `Channel` creation must have a clear owner and close policy.

### Tests

- Use `kotlinx-coroutines-test`.
- Use `runTest`, not `runBlocking`, for coroutine unit tests.
- Use virtual time with `advanceTimeBy`, `runCurrent`, and `advanceUntilIdle`.
- Inject dispatchers so tests can provide `TestDispatcher`.
- Replace `Dispatchers.Main` in JVM tests when code touches Main or Android `viewModelScope`.
- Avoid real `delay()` and `Thread.sleep()` in coroutine tests.

## Common Refactoring Patterns

### Replace Hardcoded Dispatchers

```kotlin
// Before
class Parser {
    suspend fun parse(raw: String) = withContext(Dispatchers.Default) {
        parseLargePayload(raw)
    }
}

// After
class Parser(
    private val defaultDispatcher: CoroutineDispatcher = Dispatchers.Default
) {
    suspend fun parse(raw: String) = withContext(defaultDispatcher) {
        parseLargePayload(raw)
    }
}
```

### Replace Fire-And-Forget `async`

```kotlin
// Before
scope.async {
    analytics.trackClick()
}

// After
scope.launch {
    analytics.trackClick()
}
```

### Preserve Cancellation In Result Wrappers

```kotlin
suspend fun loadSafely(): Result<User> {
    return try {
        Result.success(repository.loadUser())
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        Result.failure(e)
    }
}
```

If this pattern is repeated, prefer a small helper:

```kotlin
suspend inline fun <T> runCatchingCancellable(
    crossinline block: suspend () -> T
): Result<T> {
    return try {
        Result.success(block())
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        Result.failure(e)
    }
}
```

## Review Checklist

- [ ] Scope ownership is clear and tied to a lifecycle.
- [ ] Suspend functions do not launch ownerless background work.
- [ ] Every `Deferred` is awaited.
- [ ] Blocking work runs on IO; CPU-heavy work runs on Default; UI work runs on Main.
- [ ] Dispatchers are injectable where tests need control.
- [ ] `CancellationException` is re-thrown.
- [ ] Long loops and polling are cancellable.
- [ ] Timeout behavior is intentional.
- [ ] Flow collection in UI is lifecycle-aware.
- [ ] UI state uses `StateFlow`; events use intentionally configured `SharedFlow`.
- [ ] Channels have a clear owner and close policy.
- [ ] Coroutine tests use `runTest`, virtual time, and `TestDispatcher`.
