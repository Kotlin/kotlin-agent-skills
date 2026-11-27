# Wrapping generic Kotlin APIs for Swift

Swift Export erases generics: there are no Swift type parameters, and each `T` becomes its upper bound,
usually `(any _KotlinBridgeable)?`. For many Kotlin APIs that is not just inconvenient but breaking:

| Kotlin Swift-facing declaration | What Swift gets |
|---|---|
| `class Box<T>(val value: T)`, return type `Box<Profile>` | `Box` with `value: (any _KotlinBridgeable)?`; Swift must cast (`as? Profile`) |
| sealed **class** `ScreenState<out T>` with `Ready<T>(val data: T)` | `sealedType()` works, but `ready.value.data` is erased → casts in every `switch` |
| sealed **interface** `Result<out T>` | **no `sealedType()`** at all → `as?` chains |
| `fun headline(state: ScreenState<Profile>)`, `fun save(box: Box<Profile>)` | **not exported** (parameter is a generic class with a concrete type argument) |
| `fun render(f: (Box<Profile>) -> Unit)` | **not exported** (same rule inside a function type) |
| `fun saveAll(items: List<Box<Profile>>)`, `Set<Box<X>>`, `Map<K, Box<X>>` parameters | seen to break the bridge compilation: `compileSwiftExportMainKotlin*` → `Argument type mismatch: actual type is 'List<Box<Any?>>', but 'List<Box<Profile>>' was expected` — avoid in Swift-facing API |
| `fun all(): List<Box<Profile>>` (return) | exported as `[Box]`, erased elements |
| `interface Repository<T> { fun load(): T; fun save(item: T) }` | protocol with `load() -> (any _KotlinBridgeable)?`; a Swift implementation must accept/return erased values |
| `Flow<ScreenState<Profile>>` | `KotlinTypedFlow<ScreenState>`, the state's payload still erased |

**Rule: generic types may stay in shared Kotlin code (Android uses them), but the Swift-facing API should use
non-generic types.** Give Swift a concrete wrapper per type argument it needs, mapped in Kotlin.

## Pattern 1 — non-generic mirror type (sealed state / result classes)

The most common case: a generic UI-state or `Result<T>` hierarchy. Mirror it per screen/payload and map in Kotlin.

```kotlin
// Common generic code — unchanged, Android keeps using it
sealed class ScreenState<out T> {
    data object Loading : ScreenState<Nothing>()
    data class Ready<out T>(val data: T) : ScreenState<T>()
    data class Error(val message: String) : ScreenState<Nothing>()
}
class ProfileLoader { fun load(): Flow<ScreenState<Profile>> = ... }
fun headline(state: ScreenState<Profile>): String = ...           // not exported to Swift

// Swift-facing wrapper: same states, concrete payload
sealed class ProfileState {
    data object Loading : ProfileState()
    data class Ready(val profile: Profile) : ProfileState()
    data class Error(val message: String) : ProfileState()
}

class ProfileScreenModel(private val loader: ProfileLoader) {
    fun load(): Flow<ProfileState> = loader.load().map { it.toProfileState() }
    fun headline(state: ProfileState): String = headline(state.toScreenState())   // re-exposes a non-exported API
}

private fun ScreenState<Profile>.toProfileState(): ProfileState = when (this) {
    ScreenState.Loading -> ProfileState.Loading
    is ScreenState.Ready -> ProfileState.Ready(data)
    is ScreenState.Error -> ProfileState.Error(message)
}
private fun ProfileState.toScreenState(): ScreenState<Profile> = when (this) {
    ProfileState.Loading -> ScreenState.Loading
    is ProfileState.Ready -> ScreenState.Ready(profile)
    is ProfileState.Error -> ScreenState.Error(message)
}
```
```swift
for try await state in model.load().asAsyncSequence() {
    switch state.sealedType() {
    case .loading: ...
    case .ready(let r): show(r.value.profile)          // typed, no cast
    case .error(let e): show(e.value.message)
    }
}
// vs. the generic class: case .ready(let r): if let p = r.value.data as? Profile { ... }
```
Use a sealed **class** for the wrapper (sealed interfaces only get `sealedType()` when non-generic; a class is
the safe default). Name payload properties after their meaning (`profile`, not `data`).

## Pattern 2 — concrete subclass / sub-interface that overrides with concrete types

When the generic type is a class or interface (not a state hierarchy), declare a non-generic subtype that
**re-declares the members with the concrete type** (`override`). Swift then sees typed members, and functions that
take the subtype are exported (functions taking `Holder<Profile>` are not). Verified on Kotlin 2.5:

```kotlin
open class Holder<T>(open val value: T) { open fun get(): T = value }
class ProfileHolder(override val value: Profile) : Holder<Profile>(value) {
    override fun get(): Profile = value            // re-declare to get a typed Swift signature
}

interface Repository<T> { fun load(): T; fun save(item: T) }
interface ProfileRepository : Repository<Profile> {
    override fun load(): Profile
    override fun save(item: Profile)
}

fun takesHolder(h: Holder<Profile>): String = ...          // NOT exported
fun takesProfileHolder(h: ProfileHolder): String = ...     // exported
fun profileRepository(): ProfileRepository = ...           // Swift: any ProfileRepository, load() -> Profile
```
```swift
// generated
public final class ProfileHolder: Holder { public var value: Profile { get }; public func get() -> Profile }
public protocol ProfileRepository: KotlinBase, Repository { func load() -> Profile; func save(item: Profile) }
```
Members you don't override stay erased. This is also the way to let **Swift implement** a generic Kotlin interface
with typed signatures: have Swift implement `ProfileRepository`, and have Kotlin accept `ProfileRepository` (or the
generic `Repository<Profile>`, since it is a subtype) internally.

## Pattern 3 — concrete facade functions / classes

For generic functions and generic containers used in a few places, expose concrete entry points:

```kotlin
fun <T> cache(key: String, value: T)                      // generic, keep for Kotlin callers
fun cacheProfile(key: String, profile: Profile) = cache(key, profile)
fun cachedProfile(key: String): Profile? = cached<Profile>(key)

// collections of generic types as parameters break the build — take your own element type instead
fun saveAll(items: List<Box<Profile>>)                    // avoid in Swift-facing API (bridge may not compile)
fun saveProfiles(profiles: List<Profile>) = saveAll(profiles.map(::Box))   // Swift-facing
```
Make the generic original `internal` (or `@HiddenFromObjC`) if it's not needed from Swift, or if its signature
breaks the build.

## Pattern 4 — flows of generic types

Map in Kotlin and export a typed flow: `val profile: Flow<ProfileState> = loader.load().map { it.toProfileState() }`.
Declare the type explicitly. For `StateFlow`, map with `stateIn(scope, SharingStarted..., initial)` so Swift gets
`KotlinTypedStateFlow<ProfileState>` with a typed `.value`.

## Pattern 5 — Kotlin builders for types Swift can't create

Swift can't construct Kotlin flows or generic containers (and kotlinx factories such as `MutableStateFlow(x)`
are generic, so their Swift form is erased). When Swift must create one, e.g. when a Swift class implements a
Kotlin interface with a `Flow` property, export a typed builder:

```kotlin
interface UserRepository { val signedInUser: Flow<String>; suspend fun signInUser(user: String) }
fun mutableStateFlow(initial: String): MutableStateFlow<String> = MutableStateFlow(initial)   // typed builder for Swift
```
```swift
final class SwiftUserRepository: KotlinBase, UserRepository {
    private let user = mutableStateFlow(initial: "")            // any KotlinTypedMutableStateFlow<String>
    var signedInUser: any KotlinTypedFlow<String> { user }
    func signInUser(user: String) async throws { self.user.value = user }
}
let vm = SignInViewModel(repository: SwiftUserRepository())   // Kotlin consumes the Swift implementation
```
Same for empty/typed lists of Kotlin objects, `kotlin.Array`, ranges, etc.: give Swift a Kotlin function that
builds them.

## When to wrap and when to cast

- Wrap when Swift switches over / reads payloads in several places, when the API takes generic types as parameters
  (not exported / build break), or when Swift implements the interface.
- A single `as? Profile` at one call site is acceptable; prefer the wrapper anyway if the same type crosses the
  boundary repeatedly.
- After adding wrappers, grep the generated `<Module>.swift`: wrapper members must show concrete types, and
  generic originals that Swift no longer needs can be made `internal` to shrink the API.
- Put wrappers next to the Swift-facing API (e.g. a `ios`/`swift` sub-package or `iosMain`, if only iOS needs them),
  and keep mapping functions `private`/`internal`.
