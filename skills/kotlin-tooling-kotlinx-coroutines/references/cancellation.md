# Cancellation

## Cancellation Is Cooperative

`cancel()` sends a cancellation signal; it does not forcibly stop code. A coroutine stops when it reaches a cancellable suspension point or checks cancellation explicitly.

Long loops, CPU-heavy work, and polling must cooperate with cancellation:

```kotlin
while (isActive) {
    process()
    yield()
}
```

For batch processing:

```kotlin
for (item in items) {
    coroutineContext.ensureActive()
    process(item)
}
```

## `cancel` And `cancelAndJoin`

`job.cancel()` only requests cancellation. If following code depends on cleanup, resource release, or final state, use `cancelAndJoin()`.

```kotlin
job.cancelAndJoin()
releaseResource()
```

## `CancellationException`

`CancellationException` is part of the coroutine cancellation protocol. It is not a normal business failure. `catch (Exception)`, `catch (Throwable)`, and `runCatching` can swallow it accidentally.

```kotlin
try {
    work()
} catch (e: CancellationException) {
    throw e
} catch (e: Exception) {
    log(e)
}
```

Do not wrap suspend calls with plain `runCatching` unless cancellation is preserved:

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

## `finally` And `NonCancellable`

`finally` runs during cancellation, but suspend calls inside `finally` still respond to cancellation. If critical cleanup must call suspend APIs, wrap only that cleanup in `withContext(NonCancellable)`.

```kotlin
finally {
    withContext(NonCancellable) {
        flushAndClose()
    }
}
```

Use `NonCancellable` sparingly. It should not hide long-running work from cancellation.

## Timeout And Resource Cleanup

When a timeout means "no result", prefer `withTimeoutOrNull`. When using `withTimeout`, explicitly catch `TimeoutCancellationException` if timeout is part of normal control flow.

Resources opened inside a timeout block must be cleaned up in `finally`.

Blocking APIs may not respond to coroutine cancellation even when running on `Dispatchers.IO`. If needed, also use the underlying SDK's timeout, cancel, close, or interrupt mechanism.
