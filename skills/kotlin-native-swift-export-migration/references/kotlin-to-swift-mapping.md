# What Kotlin becomes in Swift (Swift Export, Kotlin 2.5.0+)

Each entry: Kotlin → generated Swift → how Swift uses it, plus the ObjC-export behavior it replaces.
Official mapping table: kotlinlang.org/docs/native-swift-export.html#mappings. Details below come from the Kotlin
repo goldens (`native/swift/swift-export-standalone-integration-tests/*/testData/`); for the exact shape in your
project, open the generated `<Module>.swift` (see `scripts/find-generated-swift.sh`).

## Modules and packages

- Each exported Kotlin module is a Swift module (`import <BASENAME>`); dependencies get their own modules
  (`KotlinStdlib`, `OrgJetbrainsKotlinxKotlinxCoroutinesCore`, ...). Runtime modules: `KotlinRuntime`
  (`KotlinBase`), `KotlinRuntimeSupport` (`_KotlinBridgeable`, `SealedType`, `KotlinError`),
  `KotlinCoroutineSupport` (flows, tasks). `ExportedKotlinPackages` holds the package namespaces.
- Kotlin packages are nested Swift `enum`s: `com.example.feature.Foo` →
  `ExportedKotlinPackages.com.example.feature.Foo`, usually writable as `com.example.feature.Foo`
  (`ExportedKotlinPackages` is `@_exported`). Use the fully qualified form if the first segment clashes with a
  Swift module/type name or a local variable (e.g. a local `let types = ...` shadows a package `types`).
- **No `FileNameKt` classes.** Top-level functions/properties are `static` members of the package enum:
  `com.example.feature.doThing()`, `com.example.feature.counter = 3`. Root (default-package) declarations live
  directly in the module.
- `rootPackage = "com.example"`: declarations of that exact package are aliased at module level (`Foo`,
  `doThing()`), sub-packages are aliased as namespaces (`feature.Foo`).

## Classes

```kotlin
class Foo(a: Int) { constructor(f: Float) : this(f.toInt()); fun foo(): Boolean; var x: Long = 5; var y = 0; private set }
class Hidden internal constructor(val a: Int)
open class Base { open fun greet(name: String) = ""; fun notOpen() = "" }
abstract class AbstractBase { abstract fun run(): String }
```
```swift
public final class Foo: KotlinRuntime.KotlinBase {
    public var x: Swift.Int64 { get set }
    public var y: Swift.Int32 { get }          // private setter → read-only
    public init(a: Swift.Int32)
    public init(f: Swift.Float)
    public func foo() -> Swift.Bool
}
public final class Hidden: KotlinRuntime.KotlinBase { public var a: Swift.Int32 { get } }   // no init
open class Base: KotlinRuntime.KotlinBase { public override init(); open func greet(name: Swift.String) -> Swift.String; public final func notOpen() -> Swift.String }
open class AbstractBase: KotlinRuntime.KotlinBase { open func run() -> Swift.String /* fatalError unless overridden */ }
```
- `open`/`abstract` classes and Kotlin class hierarchies are supported (the docs' "only final classes" sentence is
  outdated).
- Final classes are `final`; `open`/`abstract` classes are `open` and subclassable in Swift (overrides are
  dispatched from Kotlin; `super` calls work; `@Throws` overrides can `throw`; `suspend` overrides are `async throws`).
- **Abstract members not overridden in Swift compile fine and `fatalError` at runtime** ("Cannot invoke the
  inherited implementation of abstract member ..."). ObjC export threw `NSGenericException` instead. Override all of them.
- Instantiating an abstract class directly traps (`precondition`).
- `protected` members are **not visible** in Swift (ObjC export exposed them).
- Constructors: `init(label:)`; `@Throws` constructors are `init(...) throws`. **No default argument values.**
- Kotlin classes subclassing ObjC classes (`class X : NSObject()`) are not exported.

## Data classes, Any members

- `copy(...)` (ObjC: `doCopy`) with **every** parameter required. `componentN` not exported.
- `toString` → `description` (`"\(obj)"`), `equals` → `isEqual(_:)` and `==`, `hashCode` → `hash`/`hashValue`.
  Kotlin objects are `Hashable` (usable as `Set` elements, dictionary keys, `NavigationLink(value:)` values).
  `===` is identity. Swift subclasses may override `description`/`hash`/`isEqual` and Kotlin sees it.

## Objects and companions

```swift
MyObject.shared.doThing()               // object (same as ObjC)
Foo.Companion.shared.create()           // companion (ObjC also had Foo.companion — gone)
Bar.NamedCompanion.shared.foo()         // named companion
Sealed.Loading.shared                   // `object` subclass: never `Sealed.Loading()`
```

## Enums → native Swift enums

```kotlin
enum class Color(val hex: String) { RED("#f00"), DARK_BLUE("#00a"); fun describe() = "" }
```
```swift
public enum Color: _KotlinBridgeable, CaseIterable, LosslessStringConvertible, RawRepresentable {
    case RED; case DARK_BLUE                          // Kotlin spelling verbatim (ObjC: .red, .darkBlue)
    public var description: String { get }            // Kotlin `name`
    public var rawValue: Int32 { get }                // Kotlin `ordinal`
    public init?(_ description: String); public init?(rawValue: Int32)
    public var hex: String { get }; public func describe() -> String
}
```
- `switch` is exhaustive — remove `default:` branches. `Color.allCases` replaces `entries`/`values()`;
  `.description` replaces `name`, `.rawValue` replaces `ordinal`.
- Enum classes don't conform to the Kotlin interfaces they implement (in Swift).

## Sealed classes / interfaces → `sealedType()`

```kotlin
sealed class UiState { data object Loading : UiState(); data class Error(val message: String) : UiState(); data class Success(val items: List<Item>) : UiState() }
```
```swift
switch state.sealedType() {
case .loading: ProgressView()
case .error(let e): Text(e.value.message)          // payload is a wrapper struct; the subclass is `.value`
case .success(let s): List(s.value.items, id: \.id) { ... }
}
if case .loading = state.sealedType() { ... }
```
- Case names: lowerCamel of the subclass name (shortest unique suffix, e.g. `MyClassA.Inner` → `.myClassAInner`).
  Nested sealed parents nest: `case let .network(.timeout(t))`.
- `.unknown(...)` case appears when some inheritors aren't exported (internal, non-exported types).
- Generic sealed **interfaces** get no `sealedType()` — use `as?` casts. Subclasses are nested types:
  `UiState.Success` (ObjC: `UiStateSuccess`).

## Interfaces → protocols

```kotlin
interface Repo { fun load(id: String): Item; val name: String }
```
```swift
public protocol Repo: KotlinRuntime.KotlinBase, <BASENAME>._Repo { func load(id: String) -> Item; var name: String { get } }
func use(repo: any Repo)
```
- Values are `any Repo`. Kotlin objects of non-exported classes arrive as `_KotlinExistential<...>` that
  conform to the protocol — just use them as `any Repo`.
- **Implementing from Swift (cross-language inheritance):** the Swift class must inherit a Kotlin superclass —
  `KotlinBase` directly, or an exported Kotlin `open class` (the docs' pattern: declare `open class SwiftBase` in
  Kotlin and write `final class X: SwiftBase, Repo`). Naming `KotlinBase` needs `import KotlinRuntime` in that file:
  ```swift
  final class SwiftRepo: KotlinBase, Repo {
      let name = "swift"
      func load(id: String) -> Item { ... }
      // custom init: init(x: X) { self.x = x; super.init() }
  }
  kotlinApi.register(repo: SwiftRepo())   // Kotlin calls dispatch into Swift
  ```
  Swift structs/enums cannot conform. Kotlin default methods are inherited. (Pre-2.5 Swift Export couldn't
  instantiate such classes; `(nil as X?)!` hacks in old samples are obsolete.)
- `fun interface` → protocol + a lowercase factory taking a closure.
- To hand Swift-only APIs to Kotlin, use either a Swift implementation of a Kotlin interface (above) or Kotlin
  function-typed parameters filled with Swift closures — see `kotlin-api-preparation.md` Step 4.
- Interface members clashing with NSObject names (`hash`, `description`, `release`, ...) are dropped (by design:
  Swift resolves them to the inherited `NSObject` members, KT-90497) unless renamed with `@ObjCName(swiftName=)`.

## Inner / nested classes

`Outer.Nested()`; inner: `Outer.Inner(outer__: outer)` (ObjC: unlabeled first argument).

## Primitives, strings, optionals

| Kotlin | Swift |
|---|---|
| `Boolean` | `Bool` |
| `Byte/Short/Int/Long` | `Int8/Int16/Int32/Int64` — **`Int` is `Int32`**, convert Swift `Int` with `Int32(x)` |
| `UByte/UShort/UInt/ULong` | `UInt8/UInt16/UInt32/UInt64` |
| `Float/Double` | `Float/Double` |
| `Char` | `UInt16` (`Unicode.UTF16.CodeUnit`), not `Character` |
| `String` | `String` (copied, no identity) |
| `T?` | `T?` everywhere, including `Int32?`, `[Int32]?`, `(any Repo)?` — no `KotlinInt` boxing |
| `Unit` / `Nothing` | `Void` / `Never` |
| `Any` | the root class is `KotlinBase` (every exported class inherits it); `Any`-typed parameters/values appear as `any _KotlinBridgeable` (primitives, String, collections, Kotlin objects conform) |

## Collections

- `List<T>` → `[T]`, `Set<T>` → `Set<T>`, `Map<K, V>` → `[K: V]` (copies). `List<Int>` → `[Int32]`.
  `Map<Any, V>` → `[AnyHashable: V]`. `List<*>` → `[any _KotlinBridgeable]`.
- **Mutable collection types are not supported**: don't use `MutableList`/`MutableSet`/`MutableMap` parameters in
  Swift-facing signatures — use read-only `List`/`Set`/`Map`. As return types they are opaque
  `any ExportedKotlinPackages.kotlin.collections.MutableList` protocols, not Swift arrays. (ObjC: `NSMutableArray`,
  `KotlinMutableSet`, `KotlinMutableDictionary` — all gone.)
- **Custom types inheriting `List`/`Set`/`Map`**: the bridge compiles, but Swift can't instantiate them (KT-80417)
  and they may be ignored by the export (KT-80416). Expose a wrapper type or a read-only collection supertype.
- Map/Set keyed by an interface type → unavailable (`Never`).
- `Array<T>` → `ExportedKotlinPackages.kotlin.Array` (not generic, can't be constructed from Swift);
  `IntArray`/`ByteArray`/... likewise. Prefer `List<T>` in the API.
- Ranges: `IntRange` → `ClosedRange<Int32>`, `LongRange` → `ClosedRange<Int64>`, `OpenEndRange<Int>` → `Range<Int32>`.

## Generics — erased

```kotlin
class Box<T>(val value: T); fun <T> id(x: T): T; class Bounded<T : Shape>(val s: T)
```
```swift
public final class Box: KotlinBase { public var value: (any _KotlinBridgeable)? { get }; public init(value: (any _KotlinBridgeable)?) }
public static func id(x: (any _KotlinBridgeable)?) -> (any _KotlinBridgeable)?
public final class Bounded: KotlinBase { public init(s: any Shape) }
```
- No type parameters in Swift: write `Box(value: "x")`, read with `box.value as! String`. Drop `<...>` from all
  ObjC-era code (`Box<NSString>` → `Box`). Casts between "variances" become no-ops.
- `T` erases to its bound; unbounded `T` → `(any _KotlinBridgeable)?`. Bounded params now reject other types.
- Pass Swift values directly (`Box(value: 12 as Int32)`, `"text"`), no `NSNumber`/`NSString`. **A bare `12`
  literal passed to `_KotlinBridgeable` becomes `Double`** (Swift `Int` isn't bridgeable) — write `Int32(12)`.
- **A function whose parameter is a generic class instantiated with a concrete type (`Box<String>`,
  `ScreenState<Profile>`, also inside function types `(Box<String>) -> Unit`) is not exported.**
  `Box<*>`/`Box<Any?>` parameters are fine; return types are fine (erased).
- **Collections of such types as parameters** (`List<Box<Profile>>`, `Set<...>`, `Map<K, Box<...>>`) were seen to
  break the bridge compilation ("Argument type mismatch: actual type is 'List<Box<Any?>>'"); don't use them in
  Swift-facing signatures. Returns (`[Box]`) are fine.
- A non-generic subclass/sub-interface that **overrides** members with concrete types (`class ProfileHolder :
  Holder<Profile>` with `override val value: Profile`) gets typed Swift members, and functions taking it are
  exported. Generic sealed **classes** get `sealedType()` (payload erased); generic sealed **interfaces** don't.
  → Wrapper patterns: `wrapping-generics.md`.
- F-bounded generics (`T : Comparable<T>` on functions) and multiple upper bounds: not exported.
- `inline fun <reified T>`: not exported. Provide a non-reified overload (e.g. taking `KClass`).

## Functions

- Labels = Kotlin parameter names; `@ObjCName(swiftName = "_")` on a parameter makes it unlabeled.
- **Default arguments are not exported** — pass every argument, or add Kotlin overloads.
- Overloads keep the same name and labels (ObjC mangled them: `param_:`); disambiguate literals:
  `f(param: 2 as Int32)`, `f(param: 2.0 as Float)`.
- `vararg x: String` → `x: String...` (Swift variadic); **arrays can't be passed** — add a `List<T>` overload
  for dynamic data.
- Value classes are wrapper classes: `takeId(id: UserId(value: "42"))`, not the raw value.
- Lambdas → Swift closures (`@escaping (Int32) -> Void`); receiver lambdas get the receiver as first closure
  parameter; context parameters become a tuple first argument. Trailing closures work.
- Operators → Swift operators: `a + b`, `a += b`, `a < b`, `a[i]`, `a()` (invoke), `a ~= b` (contains).
  ObjC-era `a.plus(other: b)` / `a.get(index:)` no longer compile.
- Factory functions named like their return type are lowercased: `fun UserId(raw: String): UserId` →
  `userId(raw:)`; `MutableStateFlow(x)` → `mutableStateFlow(value:)`.
- Names conflicting with NSObject members are dropped; Swift keywords are backticked.

## Extensions

- Extension functions/properties declared in the **root package / `rootPackage`** become real Swift
  extensions: `"abc".shout()`, `user.displayName`, `Optional<Foo>` receivers → `extension Foo?`.
- Everywhere else (sub-packages): static functions with the receiver as first unlabeled argument —
  `util.shout("abc")`, `util.getDisplayName(user)`, `util.setDisplayName(user, value: "x")`.
- Member extensions: `obj.ext(receiver)`, `obj.getExtVal(receiver)`.
- ObjC: `FileKt.ext(receiver)` for platform/builtin receivers or category methods for Kotlin classes.

## Coroutines

- `suspend fun load(): Item` → `func load() async throws -> Item` — always `throws` (no `@Throws` needed),
  cancellation both ways (cancelling the Swift `Task` cancels the coroutine and throws `CancellationError`).
  No `completionHandler:` variant exists.
- Suspend lambdas → `() async throws -> T`.
- `Flow<T>` → `any KotlinTypedFlow<T>`; `StateFlow<T>` → `any KotlinTypedStateFlow<T>` (`.value`);
  `SharedFlow<T>` → `KotlinTypedSharedFlow` (`.replayCache`); `MutableStateFlow<T>` →
  `KotlinTypedMutableStateFlow` (`.value` get/set, `compareAndSet`); `MutableSharedFlow` → `emit(value:)`,
  `tryEmit(value:)`.
  ```swift
  for try await item in repo.items().asAsyncSequence() { ... }   // throwing AsyncSequence; leaving the loop cancels collection
  let current = viewModel.state.value
  ```
- Element types are preserved for concrete declarations (`Flow<User>` → `KotlinTypedFlow<User>`, `Flow<Int>` →
  `<Int32>`), but erased through generic APIs, and `Flow<Unit>` → `<any _KotlinBridgeable>`.
- Declare the type explicitly in Kotlin (`val state: StateFlow<UiState> = ...stateIn(...)`) so the Swift type is
  typed rather than inferred from a generic chain.
- Low-level: `flow.wrapped` is the raw `kotlinx.coroutines.flow.Flow` (`as! ExportedKotlinPackages.kotlinx.coroutines.flow.Flow`),
  collectable with a Swift `FlowCollector` (`class C: KotlinBase, ExportedKotlinPackages.kotlinx.coroutines.flow.FlowCollector { func emit(value: (any _KotlinBridgeable)?) async throws }`,
  `import OrgJetbrainsKotlinxKotlinxCoroutinesCore`). Prefer `asAsyncSequence()`.
- **Swift can't create Kotlin flows.** A Swift class implementing a Kotlin interface with a `Flow` member, or Swift
  code that must hand a flow to Kotlin, needs a typed Kotlin builder, e.g.
  `fun mutableStateFlow(initial: String): MutableStateFlow<String> = MutableStateFlow(initial)` → Swift keeps it and
  sets `.value`, returning it as `any KotlinTypedFlow<String>` (kotlinx's own generic factory is erased). Swift
  implements `suspend` members as `func ...() async throws`.
- Dispatcher: suspend calls and `asAsyncSequence()` run the Kotlin code on `Dispatchers.Default`. If it must run
  elsewhere, switch in Kotlin: `suspend fun load() = withContext(Dispatchers.Main) { ... }`. Update UI state on the
  Swift main actor as usual.
- Coroutine support is enabled automatically when kotlinx-coroutines is in the dependency graph; needs iOS 18+.

## Exceptions

- `@Throws(...)` functions/constructors → `throws` (untyped). `kotlin.Throwable` conforms to `Swift.Error`:
  ```swift
  do { try api.save(item) }
  catch let e as RateLimitException { show(e.message) }
  catch { ... }   // non-exported Kotlin throwables arrive as KotlinRuntimeSupport.KotlinError
  ```
  ObjC: `NSError` with `userInfo["KotlinException"]` — replace `as NSError` handling.
- Exceptions thrown from non-suspend functions without `@Throws` terminate the app — add `@Throws`.
- Swift can `throw` Kotlin exceptions from overrides; identity is preserved.

## Annotations

| Annotation | Swift Export |
|---|---|
| `@ObjCName(name, swiftName)` | still renames (swiftName preferred) classes, functions, properties, parameters |
| `@HiddenFromObjC` | hides from Swift Export too (users of it become unavailable stubs) |
| `@ShouldRefineInSwift` | **ignored** — the member is exported under its normal name (ObjC: `__name`) |
| `@Deprecated` | WARNING → `@available(*, deprecated)`, ERROR → unavailable, HIDDEN → not exported |
| `@RequiresOptIn` APIs | exported as `@_spi(Marker)`; callers need `@_spi(Marker) import <BASENAME>`; non-public markers → not exported. If exported declarations use opt-in APIs of a dependency, add `compilerOptions { optIn.add("...") }` in the exporting module |
| `@Throws` | `throws` |
| KDoc | exported as DocC `///` comments |

## Platform / cinterop types

- Foundation/UIKit types are used by their Swift names (`NSDate`, `UIViewController`); the module imports them.
- C structs, C enums, platform typealiases (`NSTimeInterval`), posix/darwin types → unavailable.
- ObjC protocols keep their ObjC/Swift name (`any NSCopying`).
