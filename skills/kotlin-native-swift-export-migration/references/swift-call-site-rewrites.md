# Rewriting Swift call sites: ObjC export → Swift Export

Approach: build, take the first error, find the declaration in the generated `<Module>.swift`, apply the rule,
repeat. Do mechanical rewrites (imports, `Kt.`, boxing, companions) across all files first, then the
semantic ones (coroutines, sealed, interfaces). Rules are numbered for reference in reports.

## Naming and namespaces

**R1. Package-qualified types.** Types outside `rootPackage` need their sub-package namespace.
```swift
// before                                   // after (rootPackage = "dev.example.common")
let person: Assignment                      let person: remote.Assignment
var vm: ISSPositionViewModel                var vm: viewmodel.ISSPositionViewModel
// no rootPackage:                          ExportedKotlinPackages.dev.example.common.remote.Assignment
```
Use the generated namespace aliases (`remote.`, `viewmodel.`). Hand-written `typealias Assignment = remote.Assignment`
in one Swift file is acceptable to keep a diff small. Watch for local variables shadowing a package name.

**R2. File facades are gone.** `KoinKt.doInitKoin()` → `di.initKoin()`; `PlatformKt.platformName()` →
`platformName()` (if in rootPackage) or `packageName.platformName()`; `TopLevelPropertyKt.counter = 1` → `pkg.counter = 1`.

**R3. Nested types stay nested.** `UiStateSuccess` → `UiState.Success`; `SealedInterfacesFirst` → `SealedInterfaces.First`.

**R4. ObjC renames disappear.** `doInit`/`doCopy`/`do<Name>` → Kotlin name; mangled overload labels
(`param_:`) → real label (R16). `@ObjCName(swiftName=)` names stay. If a Kotlin function is literally named
`init`, rename it in Kotlin (e.g. `start`) for clarity.

**R5. Imports.** `import <BASENAME>` stays only if `<SHARED_MODULE>` sets `moduleName = "<BASENAME>"` (exact
case), and only covers that module's declarations. Each exported Gradle module is its own Swift module: import the module that owns
the declaration you use (`import MagicDataLayer; import MagicDataModels`). `ExportedKotlinPackages` and
`KotlinCoroutineSupport` are re-exported — don't import them. **Add `import KotlinRuntime` in every file that names
`KotlinBase`** (e.g. R28): the generated module may import it without `@_exported` (`known-issues.md`), giving
`cannot find type 'KotlinBase' in scope`. With `MemberImportVisibility` enabled, add whatever the compiler asks
for (`KotlinStdlib`, dependency modules).

## Objects, companions, enums, data classes

**R6.** `MyObject()` (ObjC allowed calling the deprecated init) → `MyObject.shared`; sealed `object`
subclasses: `UiState.Loading.shared`.

**R7.** `Foo.companion.x` → `Foo.Companion.shared.x`.

**R8. Enums.** `.entryOne` → `.ENTRY_ONE` (exact Kotlin case name); `.name` → `.description`; `.ordinal` →
`.rawValue`; `Foo.entries`/`values()` → `Foo.allCases`; `Foo.companion.valueOf(...)` → `Foo("NAME")` (returns optional).
Exhaustive switches: drop `default:`.

**R9. Data classes.** `doCopy(...)` → `copy(...)` with all arguments; `isEqual`/`description` still work; `==` works.

## Types

**R10. Remove boxing.** `KotlinInt(value: x)` / `KotlinInt(int: x)` → `x` (as `Int32`); `[KotlinInt]` → `[Int32]`;
`KotlinBoolean(bool: b)` → `b`; `x?.int32Value`/`.intValue` → `x` / `Int(x)`; `KotlinLong` → `Int64`,
`KotlinDouble` → `Double`, `KotlinFloat` → `Float`. Optionals pass straight: `Int32?`.

**R11.** `KotlinUnit()` → `()`, `KotlinNothing` → `Never`.

**R12. Bridging wrappers.** `NSString("x")`, `"x" as NSString`, `NSNumber(value:)`, `NSArray`, `NSDictionary`
passed to Kotlin → plain Swift values. Reading erased generics/`Any`: `as! String`, `as? Int32`. Swift `Int` is not
`_KotlinBridgeable` — a literal `12` passed to an `Any`/`T` parameter becomes `Double`; write `Int32(12)`.

**R13. Generics.** Remove type arguments: `Box<NSString>(value:)` → `Box(value:)`, `Repo<User>` → `Repo`;
`KotlinArray<T>` → `kotlin.Array`. Add `as!` when reading `T` values. Bounded generics only accept the bound.

**R14. Value classes.** `takeId(id: "42")` → `takeId(id: pkg.UserId(value: "42"))`; returned values are wrapper objects (`.value`).

**R15. Mutable collections.** `NSMutableArray`, `KotlinMutableSet(set:)`, `KotlinMutableDictionary(dictionary:)` →
no equivalent (mutable collection types are not supported); change the Kotlin API to read-only `List`/`Set`/`Map`
and pass `[T]`/`Set<T>`/`[K: V]`.

## Functions

**R16. Overloads.** `f(param_: 2.0)`, `f(param__: 2)` → `f(param: 2.0 as Float)`, `f(param: 2 as Int32)`.

**R17. Default args** were never exported — no change, but check that new Swift code passes all args.

**R18. Varargs.** `f(items: KotlinArray(size:init:))` → `f(items: "a", "b")`. No array splat; for dynamic arrays
add a Kotlin `fun f(items: List<String>)` overload.

**R19. Inner classes.** `Outer.Inner(outer)` → `Outer.Inner(outer__: outer)`.

**R20. Extensions.** Root-package extensions: unchanged member-style `x.ext()`. Sub-package:
`UsualClass().ext()` → `pkg.ext(UsualClass())`; `x.extProp` → `pkg.getExtProp(x)`; platform receivers
`StringExtKt.shout("a")` → `pkg.shout("a")` (or `"a".shout()` if in rootPackage). To get member-style syntax for
important extensions, move them into the root package or add a hand-written Swift `extension` that forwards.

**R21. Operators.** `a.plus(other: b)` → `a + b`, `a.get(index: i)` → `a[i]`, `a.invoke()` → `a()`.

**R22. `@ShouldRefineInSwift`.** `__member` → `member` (now public under the normal name — beware of clashes
with the Swift refinement you wrote; rename the Swift wrapper).

**R23. `protected`** members accessed from Swift subclasses don't exist anymore — make them public in Kotlin
or add a public accessor.

## Coroutines

**R24. Suspend.**
```swift
// ObjC export completion handler
repo.getThing(succeed: true) { thing, error in ... }
// KMP-NativeCoroutines
let thing = try await asyncFunction(for: repo.getThing(succeed: true))
// SKIE / ObjC async
let thing = try await repo.getThing(succeed: true)
// Swift Export (target form for all cases)
Task {
    do { let thing = try await repo.getThing(succeed: true) }
    catch is CancellationError { }
    catch { print(error) }
}
```
Calls are always `throws`. Cancelling the Task cancels the coroutine. **With KMP-NC in compatibility mode** the
KMP-NC line above keeps compiling unchanged (`asyncFunction(for:)` is a deprecated no-op): leave it during the
migration; rewriting it is part of the KMP-NC cleanup (R25).

**R25. Flows.**
```swift
// KMP-NativeCoroutines
for try await value in asyncSequence(for: repo.numbersFlow) { }       // property name had a `Flow` suffix
// ObjC export collector
try await repo.numbers().collect(collector: Collector())              // class Collector: Kotlinx_coroutines_coreFlowCollector
// SKIE
for await value in repo.numbers() { }
// Swift Export
for try await value in repo.numbers().asAsyncSequence() { }           // typed element, throwing
let now = viewModel.state.value                                       // StateFlow current value, typed
```
**With KMP-NC in compatibility mode** (`kotlin-api-preparation.md` Step 1) existing `asyncSequence(for:)` /
`asyncFunction(for:)` call sites compile unchanged (the Combine/RxSwift helpers don't, see below): Kotlin's generated `KotlinCoroutineSupport.swift` has a deprecated
`asyncSequence(for flow: any KotlinTypedFlow<Element>)` that just calls `asAsyncSequence()`, and the
`KMPNativeCoroutinesAsync` package (plain version, e.g. `1.0.7`) has a deprecated no-op `asyncFunction(for:)`.
Leave them during the migration; each call shows a deprecation warning that names the replacement — expected,
not a failure. Casts the ObjC export needed (`as! [[LetterStatus]]`) turn into "no effect" warnings, because the elements are typed now.
Still needed even in compatibility mode: enum case names (R8: `.unguessed` → `.UNGUESSED`),
`.companion` → `.Companion.shared`, and `ArrayList<T>` in Kotlin signatures → `List<T>` (an `ArrayList` exports
as an opaque class, and `as! [T]` always fails).
**Combine / RxSwift helpers do change** (KMP-NC `SWIFT_EXPORT.md`): flows go through `asyncSequence(for:)`, suspend
functions through a closure (Swift Export suspend calls always throw, hence `try`):
```swift
// before (ObjC export)                                 // after (Swift Export compatibility mode)
createPublisher(for: clock.time)                        createPublisher(for: asyncSequence(for: clock.time))
createFuture(for: repo.getThing(succeed: true))         createFuture(for: { try await self.repo.getThing(succeed: true) })
createObservable(for: clock.time)                       createObservable(for: asyncSequence(for: clock.time))       // RxSwift
createSingle(for: repo.getThing(succeed: true))         createSingle(for: { try await self.repo.getThing(succeed: true) })
```
**Cleanup (optional, later; in Phase 5 if the user asked to drop KMP-NC):** replace the shims with `flow.asAsyncSequence()` / `try await fn()`; KMP-NC
generated names (`fooFlow`, `fooValue`, `fooNative`) → the Kotlin member name; then remove the
`KMPNativeCoroutines*` Swift packages (Combine/RxSwift users: switch to your own `AsyncSequence` → publisher
bridge first), and on the Kotlin side the annotations, the plugin and its KSP (`kotlin-api-preparation.md`
Step 1). There is no `asyncResult(for:)` shim.

**R26. SwiftUI observation (replacing SKIE `Observing` / KMP-NC `@StateObject` wrappers).**
```swift
import SwiftUI
import <BASENAME>

/// Renders `content` with the latest value of a Kotlin StateFlow.
struct Observing<Value, Content: View>: View {
    private let flow: any KotlinTypedStateFlow<Value>
    private let content: (Value) -> Content
    @State private var value: Value

    init(_ flow: any KotlinTypedStateFlow<Value>, @ViewBuilder content: @escaping (Value) -> Content) {
        self.flow = flow
        self.content = content
        _value = State(initialValue: flow.value)
    }

    var body: some View {
        // Restart when a different flow is passed in (e.g. `viewModel = di.newViewModel()` on refresh); without
        // the id the old task keeps collecting the old flow. `wrapped` is the Kotlin flow object (stable identity);
        // don't use `flow as AnyObject`: the typed flow is a struct and would get a new box on every render.
        content(value).task(id: ObjectIdentifier(flow.wrapped)) {
            value = flow.value
            do {
                for try await next in flow.asAsyncSequence() { value = next }   // `try` is required
            } catch is CancellationError {
            } catch {
                print("Observing: flow failed: \(error)")
            }
        }
    }
}
// usage unchanged from SKIE: Observing(viewModel.uiState) { state in ... }
// (compiled and run on Kotlin 2.5.0-RC2: one collection per flow, restarts after a view-model swap)
```
Observable view-model variant:
```swift
@MainActor @Observable final class ItemsModel {
    private(set) var state: viewmodel.UiState
    private let vm: viewmodel.ItemsViewModel
    init(vm: viewmodel.ItemsViewModel) { self.vm = vm; self.state = vm.uiState.value }

    /// Call from `.task { await model.observe() }` so collection stops when the view disappears.
    func observe() async {
        do { for try await s in vm.uiState.asAsyncSequence() { state = s } } catch {}
    }
}
```
Register new Swift files in the Xcode project (old-style projects need pbxproj entries).

## Sealed types, interfaces, errors

**R27. Sealed switching.**
```swift
// SKIE
switch onEnum(of: state) { case .loading: ...; case .error(let e): Text(e.message); case .success(let s): ... }
// ObjC as? chains
if let s = state as? UiStateSuccess { ... } else if let e = state as? UiStateError { ... } else { ... }
// Swift Export
switch state.sealedType() {
case .loading: ...
case .error(let e): Text(e.value.message)        // note `.value`
case .success(let s): ForEach(s.value.items, id: \.id) { ... }
}
```
Generic sealed interfaces have no `sealedType()`: keep `as?` casts against nested names (`Result.Success`).

**R28. Implementing Kotlin interfaces in Swift.**
```swift
// before
class IosFactory: NativeViewFactory { func makeView() -> UIViewController { ... } }
// after — the file needs `import KotlinRuntime` (or inherit an exported Kotlin `open class` instead of KotlinBase)
import <BASENAME>
import KotlinRuntime
final class IosFactory: KotlinBase, ui.NativeViewFactory { func makeView() -> UIViewController { ... } }
```
Applies to sealed-interface children, `FlowCollector`s, callbacks, factories. Use `super.init()` in custom inits.
Override every abstract member of Kotlin abstract classes you subclass (missing ones `fatalError` at runtime).
Kotlin `Flow` members are implemented as `var x: any KotlinTypedFlow<T>` and `suspend` members as `async throws`;
Swift can't create flows itself, so get one from a typed Kotlin builder (`mutableStateFlow(initial:)`, see
`wrapping-generics.md` Pattern 5). Generic Kotlin interfaces: implement a non-generic Kotlin sub-interface with
concrete overrides instead (`ProfileRepository : Repository<Profile>`), so Swift signatures are typed.
Passing Swift-only capabilities (CryptoKit, Keychain, StoreKit, ...) to Kotlin has two equal options: (A) Kotlin
function-typed parameters/properties filled with Swift closures (`TextHasher(hash: { ... })`), or (B) a Kotlin
interface implemented by a Swift class (inheriting `KotlinBase` or an exported Kotlin `open class`) and passed back to Kotlin
(`createSessionManager(storage: KeychainStorage())`). When to use which: `kotlin-api-preparation.md` Step 4.

**R28b. Erased generic payloads.** `if let p = ready.value.data as? Profile` / `box.value as! String` work but
spread casts everywhere — prefer adding a non-generic Kotlin wrapper (`ProfileState`, `ProfileHolder`) and switching
to it (`wrapping-generics.md`).

**R29. Errors.** `catch let e as NSError { e.kotlinException }` → `catch let e as MyKotlinException { e.message }`
(`kotlin.Throwable` conforms to `Swift.Error`; only `@Throws` functions and `suspend` functions throw into Swift).
`KotlinThrowable` → `kotlin.Throwable` (`ExportedKotlinPackages.kotlin.Throwable`). Retroactive conformances still
work: `extension kotlin.Throwable: @retroactive MyAppError {}`.

**R30. Name clashes.** Errors like `'Shape' is ambiguous for type lookup` in SwiftUI files: qualify
(`<BASENAME>.Shape`), or rename the Kotlin type (`Figure`) / `@ObjCName(swiftName = "...")`.

## Concurrency / Swift 6

Kotlin types aren't `Sendable`. Use `@preconcurrency import <BASENAME>`, keep Kotlin objects on the main actor, or wrap
them (`@unchecked Sendable` wrappers, `nonisolated(unsafe) let`), as needed by the project's language mode.

## Architectural tip

If Swift code uses Kotlin types everywhere, consider a thin adapter layer (Swift protocols/structs mapped from
Kotlin types in one place). It makes this and future migrations local (only the adapters change).
