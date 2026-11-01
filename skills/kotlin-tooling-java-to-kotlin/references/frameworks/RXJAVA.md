# RxJava to Coroutines/Flow Conversion Guide

## When This Applies

Detected when imports match `io.reactivex.*` or `rx.*`.

**Default: keep RxJava.** Moving to coroutines/Flow is a paradigm shift *and* a dependency change —
it rewrites call sites across the project and will not compile without new dependencies. Converting a
file translates the RxJava code to Kotlin syntax and leaves the reactive types in place.

Use the mappings below **only** when the project already depends on coroutines, or the user explicitly
asked for the migration.

## Key Rules

### 1. Dependency setup

A gradual migration needs `kotlinx-coroutines-core` and `kotlinx-coroutines-rx3` (or
`kotlinx-coroutines-rx2`). The bridge library provides extension functions like `asFlow()` and
`asObservable()` for interop at module boundaries. Adding these is a project-level change — ask
first; never add them as part of converting a file.

### 2. Type mapping

| RxJava | Kotlin |
|---|---|
| `Observable<T>` | `Flow<T>` |
| `Flowable<T>` | `Flow<T>` (backpressure is built-in) |
| `Single<T>` | `suspend fun`: T |
| `Maybe<T>` | `suspend fun`: T? |
| `Completable` | `suspend fun` returning `Unit` |
| `Disposable` | `Job` (from coroutines) |
| `CompositeDisposable` | `CoroutineScope` (structured concurrency) |

### 3. Operator mapping

| RxJava | Kotlin Flow |
|---|---|
| `subscribeOn(Schedulers.io())` | `flowOn(Dispatchers.IO)` |
| `observeOn(AndroidSchedulers.mainThread())` | `flowOn(Dispatchers.Main)` or collect on Main |
| `flatMap` | `flatMapMerge` or `flatMapConcat` |
| `map` | `map` (same) |
| `filter` | `filter` (same) |
| `zip` | `combine` or `zip` |
| `merge` | `merge` |
| `concat` | `flatMapConcat` |
| `onErrorReturn` | `catch { emit(default) }` |
| `doOnNext` | `onEach` |
| `subscribe()` | `collect {}` in a coroutine scope |

### 4. Error handling

RxJava's `onError` callback maps to Flow's `catch` operator or a try-catch block
wrapping the `collect` call. In suspend functions (replacing `Single`/`Completable`),
use standard try-catch.

### 5. Backpressure

Flow has built-in backpressure via suspension. There is no need for a separate
`Flowable` type — all `Flow` instances support backpressure by default.

### 6. Threading

`flowOn` changes the upstream dispatcher (analogous to `subscribeOn`). Collection
always happens on the caller's dispatcher. To collect on a specific dispatcher,
launch the collecting coroutine in the desired scope.

### 7. Lifecycle and cancellation

RxJava's `Disposable` / `CompositeDisposable` pattern is replaced by structured
concurrency. Cancelling a `CoroutineScope` cancels all child coroutines and flow
collections automatically.

---

## Example: Converting an Observable Chain to Flow

### Java Input

```java
package com.acme.data;

import io.reactivex.rxjava3.core.Observable;
import io.reactivex.rxjava3.schedulers.Schedulers;
import io.reactivex.rxjava3.android.schedulers.AndroidSchedulers;
import io.reactivex.rxjava3.disposables.CompositeDisposable;

/**
 * Repository that streams user data from a remote source.
 */
public class UserRepository {

    private final UserApi api;
    private final CompositeDisposable disposables = new CompositeDisposable();

    public UserRepository(UserApi api) {
        this.api = api;
    }

    public Observable<List<User>> getActiveUsers() {
        return api.getAllUsers()
                .subscribeOn(Schedulers.io())
                .map(users -> filterActive(users))
                .doOnNext(users -> logCount(users))
                .onErrorReturn(throwable -> Collections.emptyList());
    }

    public void observeUsers(UserCallback callback) {
        disposables.add(
            getActiveUsers()
                .observeOn(AndroidSchedulers.mainThread())
                .subscribe(
                    users -> callback.onUsers(users),
                    error -> callback.onError(error)
                )
        );
    }

    public void clear() {
        disposables.clear();
    }

    private List<User> filterActive(List<User> users) {
        return users.stream().filter(User::isActive).collect(Collectors.toList());
    }

    private void logCount(List<User> users) {
        System.out.println("Active users: " + users.size());
    }
}
```

### Kotlin Output

```kotlin
package com.acme.data

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch

/**
 * Repository that streams user data from a remote source.
 */
class UserRepository(
    private val api: UserApi
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    fun getActiveUsers(): Flow<List<User>> =
        api.getAllUsers()
            .map { users -> users.filter { it.isActive } }
            .onEach { users -> println("Active users: ${users.size}") }
            .catch { emit(emptyList()) }
            .flowOn(Dispatchers.IO)

    fun observeUsers(callback: UserCallback) {
        scope.launch {
            getActiveUsers().collect { users ->
                callback.onUsers(users)
            }
        }
    }

    fun clear() {
        scope.cancel()
    }
}
```

**Key points:**
- `Observable<List<User>>` becomes `Flow<List<User>>`.
- `subscribeOn(Schedulers.io())` becomes `flowOn(Dispatchers.IO)` at the end of the
  chain (it affects all upstream operators).
- `CompositeDisposable` is replaced by a `CoroutineScope` with `SupervisorJob`.
  Calling `scope.cancel()` cancels all active collections.
- `doOnNext` becomes `onEach`.
- `onErrorReturn` becomes `catch { emit(emptyList()) }`.
- `observeOn(AndroidSchedulers.mainThread())` is unnecessary because `scope` already
  uses `Dispatchers.Main`, and `collect` runs on the collector's dispatcher.
- Java streams (`filter` + `collect`) become Kotlin's `filter` directly on the list.
